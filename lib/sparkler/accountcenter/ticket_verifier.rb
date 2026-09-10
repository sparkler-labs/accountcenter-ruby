# frozen_string_literal: true

require "openssl"
require "json"
require "base64"
require "uri"

module Sparkler
  module AccountCenter
    # Verifies platform-issued RS256 game tickets (60s TTL JWT, header carries
    # `kid` selecting the key from the platform JWKS endpoint).
    #
    # Checks: RS256 signature (JWK → RSA from JWKS by kid), iss/aud, exp,
    # one-time jti (in-memory replay guard, entries purged at ticket expiry).
    #
    # JWKS handling: cached for 5 minutes; on fetch failure a 30s backoff window
    # suppresses repeat fetches, preferring the stale cache; with no cache the
    # verifier is FAIL-CLOSED (raises TicketError).
    class TicketVerifier
      JWKS_TTL = 300 # seconds
      JWKS_FAILURE_BACKOFF = 30 # seconds

      def initialize(jwks_url:, issuer:, audience:,
                     http: nil, open_timeout: 10, read_timeout: 10,
                     jwks_ttl: JWKS_TTL, failure_backoff: JWKS_FAILURE_BACKOFF)
        @jwks_url = jwks_url
        @issuer = issuer
        @audience = audience
        if http
          # Injected transport (tests): jwks_url is used verbatim as the path.
          @http = http
          @jwks_path = jwks_url
        else
          uri = URI.parse(jwks_url)
          origin = "#{uri.scheme}://#{uri.host}"
          origin << ":#{uri.port}" unless uri.port == uri.default_port
          @http = Http.new(base_url: origin, open_timeout: open_timeout, read_timeout: read_timeout)
          @jwks_path = uri.path
        end
        @jwks_ttl = jwks_ttl
        @failure_backoff = failure_backoff
        @mutex = Mutex.new
        @jwks_cache = nil     # { keys:, fetched_at: }
        @jwks_retry_after = 0 # wall-clock seconds; no refetch before this
        @used_jtis = {}       # jti => exp (seconds); lazily purged
      end

      # Verifies a ticket and returns its claims.
      #
      # @param token [String] the raw JWT
      # @param now [Time] injectable clock (tests)
      # @return [Types::TicketClaims]
      # @raise [TicketError] on any verification failure
      def verify!(token, now: Time.now)
        encoded_header, encoded_payload, encoded_signature = split_parts(token)
        header = decode_json_part(encoded_header)
        claims = decode_json_part(encoded_payload)
        check_header!(header)

        jwk = select_key(jwks_keys, header["kid"])
        verify_signature!(jwk, encoded_header, encoded_payload, encoded_signature)
        check_claims!(claims, now)
        record_jti!(claims["jti"], claims["exp"], now)
        Types::TicketClaims.from_h(claims)
      end

      # Test/maintenance helper: drop the JWKS cache and jti replay records.
      def reset!
        @mutex.synchronize do
          @jwks_cache = nil
          @jwks_retry_after = 0
          @used_jtis.clear
        end
      end

      private

      def split_parts(token)
        parts = token.to_s.split(".")
        raise TicketError, "malformed ticket" unless parts.size == 3 && parts.none?(&:empty?)

        parts
      end

      def decode_json_part(part)
        JSON.parse(decode_base64url(part))
      rescue JSON::ParserError, ArgumentError
        raise TicketError, "malformed ticket"
      end

      # JWT/JWK base64url is unpadded; strict urlsafe_decode64 needs padding
      def decode_base64url(value)
        Base64.urlsafe_decode64(value + ("=" * ((4 - (value.length % 4)) % 4)))
      end

      def check_header!(header)
        raise TicketError, "unsupported ticket alg: #{header['alg']}" unless header["alg"] == "RS256"
        raise TicketError, "ticket missing kid" if header["kid"].to_s.empty?
      end

      def verify_signature!(jwk, encoded_header, encoded_payload, encoded_signature)
        key = rsa_from_jwk(jwk)
        signature = decode_base64url(encoded_signature)
        valid = key.verify(OpenSSL::Digest.new("SHA256"), signature, "#{encoded_header}.#{encoded_payload}")
        raise TicketError, "invalid ticket signature" unless valid
      rescue ArgumentError
        raise TicketError, "malformed ticket"
      end

      def check_claims!(claims, now)
        check_issuer_and_audience!(claims)
        raise TicketError, "ticket expired" unless claims["exp"].is_a?(Numeric) && claims["exp"] > now.to_i
        raise TicketError, "ticket missing jti" if claims["jti"].to_s.empty?
        raise TicketError, "ticket missing sub" if claims["sub"].to_s.empty?
      end

      def check_issuer_and_audience!(claims)
        raise TicketError, "invalid ticket iss: #{claims['iss']}" if @issuer && claims["iss"] != @issuer
        raise TicketError, "invalid ticket aud: #{claims['aud']}" if @audience && claims["aud"] != @audience
      end

      def record_jti!(jti, exp, now)
        @mutex.synchronize do
          @used_jtis.delete_if { |_, expires_at| expires_at <= now.to_i }
          raise TicketError, "ticket replay detected" if @used_jtis.key?(jti)

          @used_jtis[jti] = exp.to_i
        end
      end

      # --- JWKS fetching (cached + failure backoff, fail-closed) ---

      def jwks_keys
        @mutex.synchronize do
          now = current_time
          if @jwks_cache
            return @jwks_cache[:keys] if now - @jwks_cache[:fetched_at] < @jwks_ttl
            # Failure backoff window: serve the stale cache without refetching
            return @jwks_cache[:keys] if now < @jwks_retry_after
          elsif now < @jwks_retry_after
            # No cache to fall back to: fail closed inside the backoff window
            raise TicketError, "ticket verification unavailable: failed to fetch JWKS"
          end

          fetch_and_cache_keys(now)
        end
      end

      def fetch_and_cache_keys(_now)
        keys = request_jwks
        @jwks_cache = { keys: keys, fetched_at: current_time }
        keys
      rescue TicketError
        @jwks_retry_after = current_time + @failure_backoff
        return @jwks_cache[:keys] if @jwks_cache

        raise
      end

      def request_jwks
        body = @http.request(:get, @jwks_path)
        keys = body.is_a?(Hash) ? body["keys"] : nil
        raise TicketError, "JWKS endpoint returned no keys" unless keys.is_a?(Array)

        keys
      rescue RetryableError, DeterministicError => e
        raise TicketError, "failed to fetch JWKS: #{e.message}"
      end

      def select_key(keys, kid)
        key = keys.find do |k|
          k["kty"] == "RSA" && (k["use"].nil? || k["use"] == "sig") && k["kid"] == kid
        end
        raise TicketError, "no signing key found for kid #{kid}" unless key

        key
      end

      # JWK (n/e, base64url) → OpenSSL::PKey::RSA via a DER RSAPublicKey
      # sequence, which works on every supported Ruby/OpenSSL combination.
      def rsa_from_jwk(jwk)
        n = OpenSSL::BN.new(decode_base64url(jwk["n"]), 2)
        e = OpenSSL::BN.new(decode_base64url(jwk["e"]), 2)
        sequence = OpenSSL::ASN1::Sequence([OpenSSL::ASN1::Integer(n), OpenSSL::ASN1::Integer(e)])
        OpenSSL::PKey::RSA.new(sequence.to_der)
      rescue ArgumentError, OpenSSL::ASN1::ASN1Error, OpenSSL::PKey::PKeyError
        raise TicketError, "invalid JWKS signing key"
      end

      def current_time
        Process.clock_gettime(Process::CLOCK_REALTIME)
      end
    end
  end
end

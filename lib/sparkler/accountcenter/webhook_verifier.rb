# frozen_string_literal: true

require "openssl"
require "json"

module Sparkler
  module AccountCenter
    # Verifies inbound platform webhooks.
    #
    # The platform POSTs the raw event JSON with four headers:
    #   X-Delivery-Id  — outbox key, use it to deduplicate deliveries
    #   X-Event-Type   — e.g. "account.balance_changed.v1"
    #   X-Timestamp    — Unix seconds at send time
    #   X-Signature    — hex(HMAC-SHA256(webhook_secret, "{timestamp}.{raw_body}"))
    #
    # Verification: ±5 minute replay window on the timestamp, then a
    # constant-time signature comparison. On success the parsed EventEnvelope
    # is returned; any failure raises WebhookVerificationError.
    #
    # Recommended consumer flow: verify signature → check timestamp window
    # (this class does both) → dedupe by X-Delivery-Id → ack with 2xx.
    class WebhookVerifier
      DEFAULT_TOLERANCE = 300 # seconds

      def initialize(secret:, tolerance: DEFAULT_TOLERANCE)
        raise ArgumentError, "webhook secret must not be empty" if secret.to_s.empty?

        @secret = secret
        @tolerance = tolerance
      end

      # @param raw_body [String] the exact request body, unparsed
      # @param timestamp [String, Integer] X-Timestamp header (Unix seconds)
      # @param signature [String] X-Signature header (lowercase hex)
      # @param now [Time] injectable clock (tests)
      # @return [Types::EventEnvelope] the verified, parsed event envelope
      # @raise [WebhookVerificationError]
      def verify!(raw_body:, timestamp:, signature:, now: Time.now)
        verify_timestamp!(timestamp, now)
        verify_signature!(raw_body, timestamp, signature)
        Types::EventEnvelope.from_h(parse_envelope(raw_body))
      end

      private

      def verify_timestamp!(timestamp, now)
        sent_at = Integer(timestamp, exception: false)
        if sent_at.nil?
          raise WebhookVerificationError.new("webhook timestamp is not an integer",
                                             code: "invalid_timestamp")
        end
        return if (now.to_i - sent_at).abs <= @tolerance

        raise WebhookVerificationError.new(
          "webhook timestamp outside ±#{@tolerance}s window", code: "timestamp_out_of_window"
        )
      end

      def verify_signature!(raw_body, timestamp, signature)
        expected = OpenSSL::HMAC.hexdigest("SHA256", @secret, "#{timestamp}.#{raw_body}")
        provided = signature.to_s
        if provided.bytesize == expected.bytesize &&
           OpenSSL.fixed_length_secure_compare(expected, provided)
          return
        end

        raise WebhookVerificationError.new("webhook signature mismatch", code: "invalid_signature")
      end

      def parse_envelope(raw_body)
        parsed = JSON.parse(raw_body)
        unless parsed.is_a?(Hash) && parsed["event_id"].is_a?(String)
          raise WebhookVerificationError.new("webhook body is not a valid event envelope", code: "invalid_envelope")
        end

        parsed
      rescue JSON::ParserError
        raise WebhookVerificationError.new("webhook body is not valid JSON", code: "invalid_envelope")
      end
    end
  end
end

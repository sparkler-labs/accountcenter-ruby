# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require "openssl"

module Sparkler
  module AccountCenter
    # Net::HTTP wrapper: JSON in/out, open/read timeouts (10s default), tolerant
    # error-body parsing (string code, array of messages, empty or non-JSON body)
    # and error classification per the platform contract.
    class Http
      NETWORK_ERRORS = [
        SocketError, SystemCallError, EOFError,
        Timeout::Error, Net::OpenTimeout, Net::ReadTimeout,
        OpenSSL::SSL::SSLError
      ].freeze

      attr_reader :base_url

      def initialize(base_url:, open_timeout: 10, read_timeout: 10)
        @base_url = base_url.sub(%r{/+\z}, "")
        @open_timeout = open_timeout
        @read_timeout = read_timeout
      end

      # Performs one HTTP call (no retrying here — see Client/Retry).
      #
      # @return [Object] parsed JSON body, or nil for empty bodies
      # @raise [RetryableError] on network errors/timeouts and 429/5xx
      # @raise [DeterministicError] on other 4xx
      def request(method, path, headers: {}, body: nil, query: nil)
        uri = build_uri(path, query)
        response = perform(method, uri, headers, body)
        return parse_body(response.body) if response.is_a?(Net::HTTPSuccess)

        code = error_code(response.body)
        message = "accountcenter #{method.to_s.upcase} #{uri.path} returned HTTP #{response.code}"
        message += ": #{code}" if code
        raise AccountCenter.classify_http_error(response.code.to_i, code, message)
      end

      private

      def build_uri(path, query)
        uri = URI.join("#{base_url}/", path.sub(%r{\A/+}, ""))
        return uri unless query && !query.empty?

        pairs = query.flat_map do |key, value|
          Array(value).map { |v| "#{URI.encode_www_form_component(key.to_s)}=#{URI.encode_www_form_component(v.to_s)}" }
        end
        uri.query = pairs.join("&")
        uri
      end

      def perform(method, uri, headers, body)
        request = request_class(method).new(uri)
        headers.each { |name, value| request[name] = value }
        request["Accept"] = "application/json"
        unless body.nil?
          request["Content-Type"] = "application/json"
          request.body = JSON.generate(body)
        end

        Net::HTTP.start(uri.host, uri.port,
                        use_ssl: uri.scheme == "https",
                        open_timeout: @open_timeout, read_timeout: @read_timeout) do |http|
          http.request(request)
        end
      rescue *NETWORK_ERRORS => e
        # Network error/timeout: result unknown, safe to retry (same idempotency key)
        raise RetryableError, "accountcenter #{method.to_s.upcase} #{uri.path} failed: #{e.class}: #{e.message}"
      end

      def request_class(method)
        case method
        when :get then Net::HTTP::Get
        when :post then Net::HTTP::Post
        when :patch then Net::HTTP::Patch
        when :delete then Net::HTTP::Delete
        else
          raise ArgumentError, "unsupported HTTP method: #{method}"
        end
      end

      def parse_body(raw)
        return nil if raw.nil? || raw.empty?

        JSON.parse(raw)
      rescue JSON::ParserError
        nil
      end

      # Error bodies are `{ "error": "code" }`, but user-facing endpoints may
      # return `{ "error": ["msg", ...] }` arrays; empty/non-JSON bodies yield nil.
      def error_code(raw)
        parsed = parse_body(raw)
        return nil unless parsed.is_a?(Hash)

        case (error = parsed["error"])
        when String then error
        when Array then error.first.is_a?(String) ? error.first : nil
        end
      end
    end
  end
end

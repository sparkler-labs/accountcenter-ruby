# frozen_string_literal: true

module Sparkler
  module AccountCenter
    # Fetches and caches doorkeeper client_credentials tokens.
    #
    # * cached tokens expire 60s early (configurable) so a nearly-expired token
    #   is never handed out;
    # * concurrent callers share a single refresh under a Mutex;
    # * callers react to a 401 by calling #reset! so the next call re-authenticates
    #   (Client retries the failed request once after resetting).
    class ServiceTokenProvider
      DEFAULT_EXPIRY_MARGIN = 60
      DEFAULT_TOKEN_TTL = 300 # doorkeeper fallback when expires_in is missing

      def initialize(http:, client_id:, client_secret:, scope: "funds", expiry_margin: DEFAULT_EXPIRY_MARGIN)
        @http = http
        @client_id = client_id
        @client_secret = client_secret
        @scope = scope
        @expiry_margin = expiry_margin
        @mutex = Mutex.new
        @cached = nil # { token:, expires_at: } (monotonic-ish wall time)
      end

      # @return [String] a bearer token valid for at least `expiry_margin` seconds
      def token
        cached = @cached
        return cached[:token] if fresh?(cached)

        @mutex.synchronize do
          cached = @cached
          return cached[:token] if fresh?(cached)

          fetch_token
        end
      end

      # Drop the cached token; the next #token call re-authenticates.
      def reset!
        @mutex.synchronize { @cached = nil }
      end

      private

      def fresh?(cached)
        cached && cached[:expires_at] - @expiry_margin > now
      end

      def now
        Process.clock_gettime(Process::CLOCK_REALTIME)
      end

      def fetch_token
        body = @http.request(:post, "/oauth/token", body: {
                               grant_type: "client_credentials",
                               client_id: @client_id,
                               client_secret: @client_secret,
                               scope: @scope
                             })
        token = body.is_a?(Hash) ? body["access_token"] : nil
        unless token.is_a?(String) && !token.empty?
          raise RetryableError, "accountcenter token response missing access_token"
        end

        expires_in = body["expires_in"].is_a?(Numeric) ? body["expires_in"] : DEFAULT_TOKEN_TTL
        @cached = { token: token, expires_at: now + expires_in }
        token
      end
    end
  end
end

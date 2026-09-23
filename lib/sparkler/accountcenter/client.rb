# frozen_string_literal: true

module Sparkler
  module AccountCenter
    # Platform API client. Three credential modes, chosen at construction:
    #
    #   Client.new(base_url:, client_id:, client_secret:) # service funds APIs
    #   Client.new(base_url:, bearer_token:)              # user JWT / guest token
    #   Client.new(base_url:)                             # public endpoints only
    #
    # Resources hang off the client: client.holds, client.settlements,
    # client.balances, client.auth, client.game_tokens, client.me,
    # client.withdrawals, client.leaderboard, client.event_logs.
    #
    # Automatic retries are ON by default and only ever re-fire RetryableError
    # (429/5xx/network/timeout). Retried writes are safe because every SDK write
    # carries a stable Idempotency-Key (defaulted per endpoint, overridable with
    # the `idempotency_key:` keyword) that is reused verbatim across attempts.
    class Client
      attr_reader :auth, :game_tokens, :me, :withdrawals, :leaderboard, :event_logs,
                  :holds, :settlements, :balances, :transfers

      # @param base_url [String] platform base URL, e.g. "https://api.example.com"
      # @param client_id [String, nil] doorkeeper client id (service funds mode)
      # @param client_secret [String, nil] doorkeeper client secret
      # @param scope [String] token scope, funds APIs use "funds"
      # @param bearer_token [String, nil] static Bearer token (user JWT / guest token)
      # @param open_timeout [Numeric] seconds, default 10
      # @param read_timeout [Numeric] seconds, default 10
      # @param retry_options [Hash, false] Retry.with_retries options, or false to disable
      def initialize(base_url:, client_id: nil, client_secret: nil, scope: "funds",
                     bearer_token: nil, open_timeout: 10, read_timeout: 10,
                     retry_options: {})
        validate_credentials!(base_url, client_id, client_secret, bearer_token)

        @http = Http.new(base_url: base_url, open_timeout: open_timeout, read_timeout: read_timeout)
        @base_url = @http.base_url
        @bearer_token = bearer_token
        @retry_options = retry_options
        @token_provider = client_id && ServiceTokenProvider.new(
          http: @http, client_id: client_id, client_secret: client_secret, scope: scope
        )
        mount_resources
      end

      # @return [String] platform base URL without trailing slash — handy for
      #   deriving the JWKS URL: "#{client.base_url}/api/v1/game/jwks.json"
      attr_reader :base_url

      # Test/maintenance helper: drop the cached service token so the next
      # service call re-authenticates against /oauth/token.
      def reset_token_cache!
        @token_provider&.reset!
      end

      # Internal single-shot request used by resources. Retries (when enabled)
      # wrap the whole block and only re-fire on RetryableError.
      #
      # @param bearer [String, nil] per-call Bearer override (e.g. guest upgrade)
      def request(method, path, **options)
        call = -> { perform_with_auth(method, path, **options) }
        return call.call if @retry_options == false

        Retry.with_retries(**@retry_options) { call.call }
      end

      private

      def validate_credentials!(base_url, client_id, client_secret, bearer_token)
        raise ArgumentError, "base_url is required" if base_url.to_s.empty?
        if client_id.nil? != client_secret.nil?
          raise ArgumentError, "client_id and client_secret must be given together"
        end
        return unless bearer_token && client_id

        raise ArgumentError, "bearer_token and client credentials are mutually exclusive"
      end

      def mount_resources
        @auth = Resources::Auth.new(self)
        @game_tokens = Resources::GameTokens.new(self)
        @me = Resources::Me.new(self)
        @withdrawals = Resources::Withdrawals.new(self)
        @leaderboard = Resources::Leaderboard.new(self)
        @event_logs = Resources::EventLogs.new(self)
        @holds = Resources::Holds.new(self)
        @settlements = Resources::Settlements.new(self)
        @balances = Resources::Balances.new(self)
        @transfers = Resources::Transfers.new(self)
      end

      def perform_with_auth(method, path, body: nil, query: nil, idempotency_key: nil, bearer: nil)
        @http.request(method, path, headers: build_headers(idempotency_key, bearer), body: body, query: query)
      rescue DeterministicError => e
        # 401 in service-credentials mode usually means the token was revoked
        # early: clear the cache and retry the request once with a fresh token.
        raise unless e.status == 401 && bearer.nil? && @token_provider

        @token_provider.reset!
        @http.request(method, path, headers: build_headers(idempotency_key, nil), body: body, query: query)
      end

      def build_headers(idempotency_key, bearer)
        headers = auth_headers(bearer)
        headers["Idempotency-Key"] = idempotency_key if idempotency_key
        headers
      end

      def auth_headers(bearer_override)
        token = bearer_override || @bearer_token || @token_provider&.token
        token ? { "Authorization" => "Bearer #{token}" } : {}
      end
    end
  end
end

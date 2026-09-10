# frozen_string_literal: true

module Sparkler
  module AccountCenter
    module Resources
      # Authentication endpoints. Responses are raw parsed JSON hashes
      # (`{ "token" => ..., "user" => {...} }`).
      class Auth < Base
        # Username sign-up (email optional). Pass guest_token to upgrade an
        # existing guest in place — nickname/balance/game history are kept.
        def sign_up(username:, password:, email: nil, password_confirmation: nil, guest_token: nil)
          body = { username: username, password: password }
          body[:email] = email if email
          body[:password_confirmation] = password_confirmation if password_confirmation
          request_post("/api/v1/auth/sign_up", body: body, bearer: guest_token)
        end

        # Username (or email) + password sign-in → { token:, user: }.
        def sign_in(login:, password:)
          request_post("/api/v1/auth/sign_in", body: { login: login, password: password })
        end

        # SIWE wallet sign-in/registration → { token:, user:, game_token: }.
        # `message` is the SIWE challenge message obtained from
        # GameTokens#challenge (the platform parameter is named `ticket`).
        def wallet(message:, signature:)
          request_post("/api/v1/auth/wallet", body: { ticket: message, signature: signature })
        end

        # Enabled social login providers (only those with full ENV credentials).
        def providers
          request_get("/api/v1/auth/providers")
        end
      end
    end
  end
end

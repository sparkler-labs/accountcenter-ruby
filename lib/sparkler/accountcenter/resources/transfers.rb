# frozen_string_literal: true

require "uri"

module Sparkler
  module AccountCenter
    module Resources
      # Peer-to-peer transfers between player accounts of the SAME application
      # (client_credentials + funds scope): POST /api/v1/transfers.
      #
      # Atomic same-asset debit/credit from payer to payee, bypassing any
      # revenue/reward-budget intermediary accounts. The payee account is
      # lazily created if missing. Idempotency: same (application, reference)
      # replays the original transfer; content change under the same reference
      # raises 409 idempotency_conflict. `reference` doubles as the business
      # identity (no Idempotency-Key header required by the platform, but the
      # SDK still sends one defaulting to "transfer:<reference>" so its own
      # HTTP-level retries stay safe).
      class Transfers < Base
        # @param from_user [String] payer public_id / legacy "user:<id>" / verified wallet address
        # @param to_user [String] payee public_id / legacy "user:<id>" / verified wallet address
        # @param amount [String] positive decimal string
        # @param reference [String] business-unique reference, idempotent per application
        # @param asset [String] asset code, default "points" (app allowlist)
        # @param details [Hash, nil] free-form audit details (must be an object)
        # @param idempotency_key [String] defaults to "transfer:<reference>"
        # @return [Types::Transfer]
        def create(from_user:, to_user:, amount:, reference:, asset: "points",
                   details: nil, idempotency_key: nil)
          body = {
            from_user: from_user, to_user: to_user, amount: amount,
            reference: reference, asset: asset
          }
          body[:details] = details if details
          key = idempotency_key || "transfer:#{reference}"
          Types::Transfer.from_h(request_post("/api/v1/transfers", body: body, idempotency_key: key))
        end

        # GET /api/v1/transfers/:id — only the owning application can read it.
        # @return [Types::Transfer]
        def get(id)
          Types::Transfer.from_h(
            request_get("/api/v1/transfers/#{URI.encode_www_form_component(id.to_s)}")
          )
        end

        # GET /api/v1/transfers/by-reference/:reference — polling/reconciliation.
        # Only the owning application can read it; other applications / unknown
        # references return 404 (existence is not exposed).
        # @return [Types::Transfer]
        def by_reference(reference)
          Types::Transfer.from_h(
            request_get("/api/v1/transfers/by-reference/#{URI.encode_www_form_component(reference)}")
          )
        end
      end
    end
  end
end

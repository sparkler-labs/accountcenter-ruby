# frozen_string_literal: true

require "uri"

module Sparkler
  module AccountCenter
    module Resources
      # Funds holds (client_credentials + funds scope).
      #
      # State machine: reserved → executing → captured; reserved → released /
      # expired. Crash recovery: GET the hold by id and continue from its state.
      class Holds < Base
        # Reserve funds for one action (POST /api/v1/holds, 201).
        #
        # The Idempotency-Key MUST equal action_id on the wire (platform rule);
        # the SDK defaults it accordingly. Result-unknown retries must reuse the
        # same action_id so the platform replays the original hold.
        #
        # @param user [String] platform user public_id (UUID), legacy
        #   "user:<id>" player id, or a verified wallet address
        # @param amount [String] positive decimal string
        # @param action_id [String] unique action id (also the idempotency key)
        # @param asset [String] asset code, default "points" (app allowlist)
        # @param expires_in [Integer] hold TTL seconds, default 300 server-side
        # @return [Types::Hold]
        def create(user:, amount:, action_id:, asset: "points", expires_in: nil, idempotency_key: nil)
          body = { user: user, amount: amount, asset: asset, action_id: action_id }
          body[:expires_in] = expires_in if expires_in
          Types::Hold.from_h(request_post("/api/v1/holds", body: body,
                                                           idempotency_key: idempotency_key || action_id))
        end

        # reserved (unexpired) → executing; expired/converted → 409 state_conflict.
        # @return [Types::Hold]
        def execution(hold_id, idempotency_key: nil)
          Types::Hold.from_h(request_post("/api/v1/holds/#{escape(hold_id)}/execution",
                                          idempotency_key: idempotency_key || "#{hold_id}:execution"))
        end

        # executing → captured: atomic debit + ledger entry.
        # @return [Types::HoldCaptureResult]
        def capture(hold_id, idempotency_key: nil)
          Types::HoldCaptureResult.from_h(request_post("/api/v1/holds/#{escape(hold_id)}/capture",
                                                       idempotency_key: idempotency_key || "#{hold_id}:capture"))
        end

        # reserved (unexpired) or executing → released.
        # @return [Types::Hold]
        def release(hold_id, idempotency_key: nil)
          Types::Hold.from_h(request_post("/api/v1/holds/#{escape(hold_id)}/release",
                                          idempotency_key: idempotency_key || "#{hold_id}:release"))
        end

        # Look up a hold (crash recovery). Only the owning game can read it —
        # other games get 404 not_found.
        # @return [Types::Hold]
        def get(hold_id)
          Types::Hold.from_h(request_get("/api/v1/holds/#{escape(hold_id)}"))
        end

        private

        def escape(value)
          URI.encode_www_form_component(value.to_s)
        end
      end
    end
  end
end

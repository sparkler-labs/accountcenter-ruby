# frozen_string_literal: true

require "uri"

module Sparkler
  module AccountCenter
    module Resources
      # Withdrawal requests (Bearer user JWT). Creating a withdrawal immediately
      # reserves the available balance via a platform hold; on-chain payout is
      # performed by an external process. Responses are raw parsed JSON hashes.
      class Withdrawals < Base
        # GET /api/v1/withdrawals (newest first)
        def list
          request_get("/api/v1/withdrawals")
        end

        # GET /api/v1/withdrawals/:id
        def get(id)
          request_get("/api/v1/withdrawals/#{URI.encode_www_form_component(id.to_s)}")
        end

        # POST /api/v1/withdrawals — `dest` must be one of the user's verified
        # wallet addresses; insufficient available balance fails the whole
        # request with 422.
        def create(amount:, dest:)
          request_post("/api/v1/withdrawals", body: { amount: amount, dest: dest })
        end
      end
    end
  end
end

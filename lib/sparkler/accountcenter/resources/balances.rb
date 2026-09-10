# frozen_string_literal: true

module Sparkler
  module AccountCenter
    module Resources
      # Batch authoritative balances (client_credentials + funds scope):
      # GET /api/v1/balances?players=a,b,...
      #
      # The platform caps each call at 100 players (422 too_many_players beyond
      # that); this resource slices larger lists and merges the results.
      # Response is a plain Hash of player identifier => decimal-string balance;
      # every requested player is present (unknown/zero accounts report "0").
      class Balances < Base
        BATCH_SIZE = 100

        # @param players [Array<String>] public_ids / legacy player ids / wallet addresses
        # @return [Hash{String => String}] player => decimal-string balance
        def get(players)
          Array(players).each_slice(BATCH_SIZE).reduce({}) do |merged, batch|
            body = fetch_batch(batch)
            merged.merge(body.is_a?(Hash) ? body["balances"] || {} : {})
          end
        end

        private

        # NOTE: Base#get has a different signature (path), so hit the client
        # directly here to avoid dispatching back into this #get.
        def fetch_batch(batch)
          @client.request(:get, "/api/v1/balances", query: { players: batch.join(",") })
        end
      end
    end
  end
end

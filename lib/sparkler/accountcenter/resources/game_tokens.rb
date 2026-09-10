# frozen_string_literal: true

module Sparkler
  module AccountCenter
    module Resources
      # Game ticket issuance. Tickets are 60s RS256 JWTs (verify them with
      # TicketVerifier); every connect/reconnect fetches a fresh ticket because
      # the jti is single-use.
      class GameTokens < Base
        # SIWE challenge for an address (no authentication).
        # @return [Hash] the SIWE message fields to sign
        def challenge(address:, chain_id:)
          request_get("/api/v1/game_tokens/new", query: { address: address, chain_id: chain_id })
        end

        # Fetch a ticket with a signed SIWE challenge (no session needed)...
        # @return [Hash] includes "ticket"
        def create_with_siwe(message:, signature:)
          request_post("/api/v1/game_tokens", body: { ticket: message, signature: signature })
        end

        # ...or with the caller's Bearer JWT (bearer-mode client).
        # @return [Hash] includes "ticket"
        def create(bearer: nil)
          request_post("/api/v1/game_tokens", bearer: bearer)
        end

        # No-authentication guest ticket. On first play the platform creates a
        # real guest user with a nickname; persist guest_token (30 days) and use
        # it as a Bearer token to fetch future tickets for the same identity.
        # @return [Types::GuestTicket]
        def guest
          Types::GuestTicket.from_h(request_post("/api/v1/game_tokens/guest"))
        end
      end
    end
  end
end

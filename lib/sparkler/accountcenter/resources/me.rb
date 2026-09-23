# frozen_string_literal: true

require "uri"

module Sparkler
  module AccountCenter
    module Resources
      # Current-user profile endpoints (Bearer user JWT / guest token).
      # Responses are raw parsed JSON hashes.
      class Me < Base
        # GET /api/v1/me
        def get
          request_get("/api/v1/me")
        end

        # PATCH /api/v1/me — email/nickname/flag_style/password. Changing the
        # password on an account that already has one requires current_password.
        def update(email: nil, nickname: nil, flag_style: nil,
                   password: nil, password_confirmation: nil, current_password: nil)
          body = {}
          body[:email] = email unless email.nil?
          body[:nickname] = nickname unless nickname.nil?
          body[:flag_style] = flag_style unless flag_style.nil?
          body[:password] = password unless password.nil?
          body[:password_confirmation] = password_confirmation unless password_confirmation.nil?
          body[:current_password] = current_password unless current_password.nil?
          request_patch("/api/v1/me", body: body)
        end

        # POST /api/v1/me/addresses — link a wallet address via SIWE.
        #
        # @param ticket [String] the OPAQUE ticket field from the
        #   GameTokens#challenge response (the wallet signs
        #   challenge["message"]; the platform recovers it from this ticket)
        # @param signature [String] wallet signature over challenge["message"]
        def create_address(ticket:, signature:)
          request_post("/api/v1/me/addresses", body: { ticket: ticket, signature: signature })
        end

        # DELETE /api/v1/me/addresses/:id
        def delete_address(id)
          request_delete("/api/v1/me/addresses/#{URI.encode_www_form_component(id.to_s)}")
        end

        # DELETE /api/v1/me/identities/:id — unlink a social identity.
        def delete_identity(id)
          request_delete("/api/v1/me/identities/#{URI.encode_www_form_component(id.to_s)}")
        end

        # GET /api/v1/me/ledger_entries — the calling user's own ledger entry
        # stream (Bearer user JWT), newest first. Read-only: an unknown asset
        # code raises 422 unknown_asset, and a user without an account for the
        # asset gets an empty list (no lazy account creation).
        #
        # @param asset [String] asset code, default "points"
        # @param page [Integer] 1-based page index, default 1
        # @param per_page [Integer] page size, default 20, capped at 100 by the platform
        # @return [Hash] raw parsed JSON: { "entries" => [...], "meta" => { page, per_page, total } }
        def ledger_entries(asset: "points", page: 1, per_page: 20)
          request_get(
            "/api/v1/me/ledger_entries",
            query: { asset: asset, page: page, per_page: per_page }
          )
        end
      end
    end
  end
end

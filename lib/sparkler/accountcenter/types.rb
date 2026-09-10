# frozen_string_literal: true

module Sparkler
  module AccountCenter
    # Resource value types. Fields mirror the platform's serialization one to
    # one: amounts are decimal STRINGS (decimal(36,18) — never coerce to Float)
    # and timestamps are ISO8601 strings.
    module Types
      # Adds .from_h(hash) to a Struct class: symbol keys, unknown keys ignored
      # (the platform may add fields without breaking the SDK).
      module Parseable
        def from_h(hash)
          hash = {} unless hash.is_a?(Hash)
          new(**hash.each_with_object({}) do |(key, value), attrs|
            sym = key.to_sym
            attrs[sym] = value if members.include?(sym)
          end)
        end
      end

      # Ledger transaction summary attached to hold captures / posted settlements.
      LedgerTransactionSummary = Struct.new(:id, :reference, :type, :state, keyword_init: true) do
        extend Parseable
      end

      # Hold state machine: reserved → executing → captured;
      # reserved → released / expired.
      Hold = Struct.new(:id, :state, :asset, :amount, :action_id, :account_id, :user,
                        :expires_at, :executed_at, :captured_at, :released_at, :created_at,
                        keyword_init: true) do
        extend Parseable

        def terminal?
          %w[captured released expired].include?(state)
        end
      end

      # Response of POST /api/v1/holds/:id/capture: hold + debit transaction.
      HoldCaptureResult = Struct.new(:hold, :ledger_transaction, keyword_init: true) do
        def self.from_h(hash)
          hash = {} unless hash.is_a?(Hash)
          txn = hash["ledger_transaction"] || hash[:ledger_transaction]
          new(
            hold: Hold.from_h(hash),
            ledger_transaction: txn.nil? ? nil : LedgerTransactionSummary.from_h(txn)
          )
        end
      end

      # Settlement state machine: submitted → posted / rejected.
      Settlement = Struct.new(:id, :reference, :state, :asset, :amount, :user,
                              :reject_reason, :details, :ledger_transaction, :created_at,
                              keyword_init: true) do
        extend Parseable

        def self.from_h(hash)
          parsed = super
          txn = parsed.ledger_transaction
          parsed.ledger_transaction = LedgerTransactionSummary.from_h(txn) if txn.is_a?(Hash)
          parsed
        end

        def terminal?
          %w[posted rejected].include?(state)
        end
      end

      # Unified webhook event envelope (schema_version is currently always 1).
      # `event_id` is the global idempotency key; `data` keeps raw string amounts.
      EventEnvelope = Struct.new(:event_id, :schema_version, :event_type, :occurred_at,
                                 :aggregate_type, :aggregate_id, :aggregate_version,
                                 :correlation_id, :data, keyword_init: true) do
        extend Parseable
      end

      # Response of POST /api/v1/game_tokens/guest: a 60s RS256 ticket plus the
      # durable 30-day guest_token used to fetch future tickets.
      GuestTicket = Struct.new(:ticket, :guest_token, :player_id, :nickname, keyword_init: true) do
        extend Parseable
      end

      # Claims of a verified RS256 game ticket (see TicketVerifier).
      TicketClaims = Struct.new(:iss, :sub, :aud, :iat, :exp, :jti, :session_id,
                                :address, :player_id, :nickname, :flag_style, :balance,
                                keyword_init: true) do
        extend Parseable
      end
    end
  end
end

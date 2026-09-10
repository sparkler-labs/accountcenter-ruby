# frozen_string_literal: true

require "uri"

module Sparkler
  module AccountCenter
    module Resources
      # Settlement documents (client_credentials + funds scope).
      #
      # Acceptance (202) persists `submitted` and attempts posting synchronously;
      # 202 does NOT mean posted — poll #wait_for or consume the
      # settlement.posted.v1 / settlement.rejected.v1 events for the outcome.
      # Same-game same-reference resubmission returns the original document
      # without double-posting. `rejected` is never auto-reversed: fix and
      # submit a NEW reference.
      class Settlements < Base
        TERMINAL_STATES = %w[posted rejected].freeze
        DEFAULT_WAIT_TIMEOUT = 8.0   # seconds
        DEFAULT_WAIT_INTERVAL = 0.5  # seconds

        # Submit a settlement (POST /api/v1/settlements, 202).
        #
        # @param user [String] platform user public_id / legacy player id / wallet address
        # @param amount [String] positive decimal string (positive net only)
        # @param reference [String] business-unique reference, idempotent per game
        # @param asset [String] default "points"; a non-allowlisted asset is not
        #   rejected at the door but lands `rejected` with reject_reason
        # @param details [Hash] free-form audit details (must be an object)
        # @param idempotency_key [String] defaults to "settlement:<reference>"
        # @return [Types::Settlement]
        def create(user:, amount:, reference:, asset: "points", details: nil, idempotency_key: nil)
          body = { user: user, amount: amount, reference: reference, asset: asset }
          body[:details] = details if details
          key = idempotency_key || "settlement:#{reference}"
          Types::Settlement.from_h(request_post("/api/v1/settlements", body: body, idempotency_key: key))
        end

        # Fetch by business reference (polling/reconciliation). Only the owning
        # game can read it — other games get 404 not_found.
        # @return [Types::Settlement]
        def by_reference(reference)
          Types::Settlement.from_h(
            request_get("/api/v1/settlements/by-reference/#{URI.encode_www_form_component(reference)}")
          )
        end

        # Poll a settlement until a terminal state (posted/rejected).
        #
        # A timeout raises RetryableError because the result is still unknown:
        # keep querying by the SAME reference later (next flush / startup
        # recovery) — never resubmit under a different reference.
        #
        # @return [Types::Settlement] the terminal settlement
        # @raise [RetryableError] on overall timeout
        def wait_for(reference, timeout: DEFAULT_WAIT_TIMEOUT, interval: DEFAULT_WAIT_INTERVAL,
                     until_states: TERMINAL_STATES, sleeper: ->(seconds) { sleep(seconds) })
          deadline = monotonic + timeout
          loop do
            settlement = by_reference(reference)
            return settlement if until_states.include?(settlement.state)
            if monotonic + interval > deadline
              raise RetryableError, "settlement #{reference} still #{settlement.state} after #{timeout}s"
            end

            sleeper.call(interval)
          end
        end

        private

        def monotonic
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end
      end
    end
  end
end

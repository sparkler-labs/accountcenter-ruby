# frozen_string_literal: true

module Sparkler
  module AccountCenter
    # Base class for every error raised by this SDK.
    #
    # Error classification follows the platform contract: network errors,
    # timeouts, HTTP 429 and 5xx mean the result is UNKNOWN and the request may
    # be safely retried with the same Idempotency-Key (RetryableError); every
    # other 4xx is a definitive result (DeterministicError) and must not be
    # retried as-is.
    class Error < StandardError
      # @return [String, nil] platform error code from a `{ "error": code }` body
      attr_reader :code
      # @return [Integer, nil] HTTP status; nil for network errors/timeouts
      attr_reader :status

      def initialize(message, code: nil, status: nil)
        @code = code
        @status = status
        super(message)
      end

      def retryable?
        false
      end
    end

    # Result-unknown error (429 / 5xx / network error / timeout). Writes may be
    # retried with the SAME Idempotency-Key: the platform replays the stored
    # response instead of duplicating holds/settlements.
    class RetryableError < Error
      def retryable?
        true
      end
    end

    # Definitive business/client error (400/401/402/403/404/409/422). Retrying
    # returns the same result. Note: 409 idempotency_conflict means the same key
    # was reused with a different body — a caller key-management bug.
    class DeterministicError < Error
    end

    # Raised by WebhookVerifier when signature/timestamp verification fails.
    class WebhookVerificationError < Error
    end

    # Raised by TicketVerifier when an RS256 game ticket fails verification
    # (malformed, bad signature, wrong iss/aud, expired, replayed jti, JWKS
    # unavailable). Ticket verification is fail-closed.
    class TicketError < Error
    end

    # Classify an HTTP error response into RetryableError / DeterministicError.
    # 429 and 5xx are result-unknown; everything else is definitive.
    def self.classify_http_error(status, code, message)
      if status == 429 || status >= 500
        RetryableError.new(message, code: code, status: status)
      else
        DeterministicError.new(message, code: code, status: status)
      end
    end
  end
end

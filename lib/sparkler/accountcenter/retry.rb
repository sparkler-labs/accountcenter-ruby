# frozen_string_literal: true

module Sparkler
  module AccountCenter
    # Exponential-backoff retry helper. Only RetryableError (result unknown) is
    # retried; DeterministicError and any other exception propagate immediately.
    #
    # Contract: retried writes must carry a stable Idempotency-Key and every
    # attempt must reuse the SAME key — the block is replayed verbatim, never
    # fold the attempt number into the key.
    module Retry
      DEFAULTS = {
        max_attempts: 3,   # total attempts, first included
        base_delay: 0.5,   # first backoff in seconds; attempt n waits base * 2^(n-1)
        max_delay: 5.0,    # backoff ceiling in seconds
        jitter: true       # full jitter: actual wait is uniform in [0, delay]
      }.freeze

      module_function

      # @yieldparam attempt [Integer] 1-based attempt number
      # @return the block's first successful result
      def with_retries(sleeper: ->(seconds) { sleep(seconds) }, **options)
        opts = DEFAULTS.merge(options)
        last_error = nil

        (1..opts[:max_attempts]).each do |attempt|
          return yield(attempt)
        rescue RetryableError => e
          last_error = e
          break if attempt >= opts[:max_attempts]

          sleeper.call(delay_for(attempt, opts))
        end
        raise last_error
      end

      def delay_for(attempt, opts)
        exponential = [opts[:base_delay] * (2**(attempt - 1)), opts[:max_delay]].min
        opts[:jitter] ? rand * exponential : exponential
      end
    end
  end
end

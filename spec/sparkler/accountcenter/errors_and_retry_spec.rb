# frozen_string_literal: true

RSpec.describe Sparkler::AccountCenter do
  describe ".classify_http_error" do
    it "classifies 429 as retryable" do
      error = described_class.classify_http_error(429, nil, "rate limited")
      expect(error).to be_a(Sparkler::AccountCenter::RetryableError)
      expect(error).to be_retryable
      expect(error.status).to eq(429)
    end

    it "classifies every 5xx as retryable" do
      [500, 502, 503, 504, 599].each do |status|
        error = described_class.classify_http_error(status, "boom", "server error")
        expect(error).to be_a(Sparkler::AccountCenter::RetryableError), "expected #{status} to be retryable"
      end
    end

    it "classifies definitive 4xx codes as deterministic" do
      {
        400 => "idempotency_key_required",
        401 => "unauthorized",
        402 => "insufficient_funds",
        403 => "insufficient_scope",
        404 => "not_found",
        409 => "state_conflict",
        422 => "invalid_amount"
      }.each do |status, code|
        error = described_class.classify_http_error(status, code, "nope")
        expect(error).to be_a(Sparkler::AccountCenter::DeterministicError), "expected #{status} to be deterministic"
        expect(error).not_to be_retryable
        expect(error.code).to eq(code)
        expect(error.status).to eq(status)
      end
    end
  end
end

RSpec.describe Sparkler::AccountCenter::Retry do
  let(:no_sleep) { ->(_seconds) {} }

  it "returns the first successful result without retrying" do
    attempts = 0
    result = described_class.with_retries(sleeper: no_sleep) do
      attempts += 1
      :ok
    end
    expect(result).to eq(:ok)
    expect(attempts).to eq(1)
  end

  it "retries RetryableError with the same block until success" do
    attempts = 0
    result = described_class.with_retries(sleeper: no_sleep) do
      attempts += 1
      raise Sparkler::AccountCenter::RetryableError, "unknown" if attempts < 3

      :recovered
    end
    expect(result).to eq(:recovered)
    expect(attempts).to eq(3)
  end

  it "re-raises the last RetryableError after max_attempts" do
    attempts = 0
    expect do
      described_class.with_retries(max_attempts: 2, sleeper: no_sleep) do
        attempts += 1
        raise Sparkler::AccountCenter::RetryableError, "still unknown"
      end
    end.to raise_error(Sparkler::AccountCenter::RetryableError, "still unknown")
    expect(attempts).to eq(2)
  end

  it "never retries DeterministicError" do
    attempts = 0
    expect do
      described_class.with_retries(sleeper: no_sleep) do
        attempts += 1
        raise Sparkler::AccountCenter::DeterministicError, "definitive"
      end
    end.to raise_error(Sparkler::AccountCenter::DeterministicError)
    expect(attempts).to eq(1)
  end

  it "computes exponential delays capped at max_delay with full jitter" do
    opts = { base_delay: 0.5, max_delay: 5.0, jitter: false }
    expect(described_class.delay_for(1, opts)).to eq(0.5)
    expect(described_class.delay_for(2, opts)).to eq(1.0)
    expect(described_class.delay_for(3, opts)).to eq(2.0)
    expect(described_class.delay_for(10, opts)).to eq(5.0)

    jittered = described_class.delay_for(3, opts.merge(jitter: true))
    expect(jittered).to be_between(0.0, 2.0)
  end
end

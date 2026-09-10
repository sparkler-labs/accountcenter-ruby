# frozen_string_literal: true

require "openssl"

RSpec.describe Sparkler::AccountCenter::WebhookVerifier do
  subject(:verifier) { described_class.new(secret: "whsec") }

  let(:raw_body) do
    {
      event_id: "hold-capture:act-1",
      schema_version: 1,
      event_type: "hold.captured.v1",
      occurred_at: "2026-09-10T08:00:00.000000Z",
      aggregate_type: "Ledger::Hold",
      aggregate_id: 12,
      aggregate_version: 3,
      correlation_id: nil,
      data: { action_id: "act-1", amount: "50" }
    }.to_json
  end
  let(:now) { Time.at(1_800_000_000) }
  let(:timestamp) { now.to_i.to_s }
  let(:signature) { OpenSSL::HMAC.hexdigest("SHA256", "whsec", "#{timestamp}.#{raw_body}") }

  it "verifies a well-formed delivery and returns the parsed envelope" do
    envelope = verifier.verify!(raw_body: raw_body, timestamp: timestamp, signature: signature, now: now)
    expect(envelope).to be_a(Sparkler::AccountCenter::Types::EventEnvelope)
    expect(envelope.event_id).to eq("hold-capture:act-1")
    expect(envelope.event_type).to eq("hold.captured.v1")
    expect(envelope.aggregate_version).to eq(3)
    expect(envelope.data).to eq("action_id" => "act-1", "amount" => "50")
  end

  it "rejects a bad signature" do
    bad = OpenSSL::HMAC.hexdigest("SHA256", "wrong-secret", "#{timestamp}.#{raw_body}")
    expect { verifier.verify!(raw_body: raw_body, timestamp: timestamp, signature: bad, now: now) }
      .to raise_error(Sparkler::AccountCenter::WebhookVerificationError) { |e|
        expect(e.code).to eq("invalid_signature")
      }
  end

  it "rejects a signature computed over a tampered body" do
    expect do
      verifier.verify!(raw_body: raw_body.sub("50", "50000"),
                       timestamp: timestamp, signature: signature, now: now)
    end.to raise_error(Sparkler::AccountCenter::WebhookVerificationError)
  end

  it "rejects timestamps outside the ±5 minute replay window" do
    stale = (now.to_i - 301).to_s
    sig = OpenSSL::HMAC.hexdigest("SHA256", "whsec", "#{stale}.#{raw_body}")
    expect { verifier.verify!(raw_body: raw_body, timestamp: stale, signature: sig, now: now) }
      .to raise_error(Sparkler::AccountCenter::WebhookVerificationError) { |e|
        expect(e.code).to eq("timestamp_out_of_window")
      }
  end

  it "accepts timestamps at the window edge" do
    edge = (now.to_i - 300).to_s
    sig = OpenSSL::HMAC.hexdigest("SHA256", "whsec", "#{edge}.#{raw_body}")
    envelope = verifier.verify!(raw_body: raw_body, timestamp: edge, signature: sig, now: now)
    expect(envelope.event_id).to eq("hold-capture:act-1")
  end

  it "rejects non-JSON bodies" do
    body = "not json"
    sig = OpenSSL::HMAC.hexdigest("SHA256", "whsec", "#{timestamp}.#{body}")
    expect { verifier.verify!(raw_body: body, timestamp: timestamp, signature: sig, now: now) }
      .to raise_error(Sparkler::AccountCenter::WebhookVerificationError) { |e|
        expect(e.code).to eq("invalid_envelope")
      }
  end
end

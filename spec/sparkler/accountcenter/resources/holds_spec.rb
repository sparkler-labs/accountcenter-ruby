# frozen_string_literal: true

RSpec.describe Sparkler::AccountCenter::Resources::Holds do
  let(:client) do
    Sparkler::AccountCenter::Client.new(base_url: BASE_URL, client_id: "cid", client_secret: "sec")
  end

  let(:hold_json) do
    { id: 42, state: "reserved", asset: "points", amount: "50", action_id: "revive:42",
      account_id: 9, user: "u-uuid", expires_at: "2026-09-10T08:05:00Z", executed_at: nil,
      captured_at: nil, released_at: nil, created_at: "2026-09-10T08:00:00Z" }
  end

  before { stub_service_token }

  it "creates a hold with Idempotency-Key equal to action_id by default" do
    stub = stub_request(:post, "#{BASE_URL}/api/v1/holds")
           .with(body: { user: "u-uuid", amount: "50", asset: "points",
                         action_id: "revive:42" }.to_json,
                 headers: { "Idempotency-Key" => "revive:42",
                            "Authorization" => "Bearer svc-token" })
           .to_return(status: 201, body: hold_json.to_json)

    hold = client.holds.create(user: "u-uuid", amount: "50", action_id: "revive:42")
    expect(stub).to have_been_requested
    expect(hold).to be_a(Sparkler::AccountCenter::Types::Hold)
    expect(hold.state).to eq("reserved")
    expect(hold.amount).to eq("50")
    expect(hold.terminal?).to be(false)
  end

  it "allows overriding the idempotency key" do
    stub = stub_request(:post, "#{BASE_URL}/api/v1/holds")
           .with(headers: { "Idempotency-Key" => "custom-key" })
           .to_return(status: 201, body: hold_json.to_json)
    client.holds.create(user: "u-uuid", amount: "50", action_id: "revive:42",
                        idempotency_key: "custom-key")
    expect(stub).to have_been_requested
  end

  it "sends expires_in when given" do
    stub = stub_request(:post, "#{BASE_URL}/api/v1/holds")
           .with(body: /"expires_in":600/)
           .to_return(status: 201, body: hold_json.to_json)
    client.holds.create(user: "u-uuid", amount: "50", action_id: "revive:42", expires_in: 600)
    expect(stub).to have_been_requested
  end

  it "uses stable default idempotency keys for execution/capture/release" do
    %w[execution capture release].each do |action|
      stub = stub_request(:post, "#{BASE_URL}/api/v1/holds/42/#{action}")
             .with(headers: { "Idempotency-Key" => "42:#{action}" })
             .to_return(status: 200, body: hold_json.merge(state: "executing").to_json)
      client.holds.public_send(action, 42)
      expect(stub).to have_been_requested
    end
  end

  it "capture returns the hold plus the ledger transaction summary" do
    txn = { id: 5, reference: "hold-capture:revive:42", type: "hold_capture", state: "posted" }
    stub_request(:post, "#{BASE_URL}/api/v1/holds/42/capture")
      .to_return(status: 200, body: hold_json.merge(state: "captured", ledger_transaction: txn).to_json)

    result = client.holds.capture(42)
    expect(result.hold.state).to eq("captured")
    expect(result.hold.terminal?).to be(true)
    expect(result.ledger_transaction.reference).to eq("hold-capture:revive:42")
  end

  it "maps 402 insufficient_funds to a deterministic error" do
    stub_request(:post, "#{BASE_URL}/api/v1/holds")
      .to_return(status: 402, body: { error: "insufficient_funds" }.to_json)
    expect { client.holds.create(user: "u-uuid", amount: "50", action_id: "revive:42") }
      .to raise_error(Sparkler::AccountCenter::DeterministicError) { |e|
        expect(e.code).to eq("insufficient_funds")
        expect(e.status).to eq(402)
      }
  end
end

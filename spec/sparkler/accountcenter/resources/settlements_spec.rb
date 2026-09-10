# frozen_string_literal: true

RSpec.describe Sparkler::AccountCenter::Resources::Settlements do
  let(:client) do
    Sparkler::AccountCenter::Client.new(base_url: BASE_URL, client_id: "cid", client_secret: "sec")
  end

  let(:settlement_json) do
    { id: 3, reference: "reward-42", state: "submitted", asset: "points", amount: "120",
      user: "u-uuid", reject_reason: nil, details: { protocol: "my-game-settlement/v1" },
      ledger_transaction: nil, created_at: "2026-09-10T08:00:00Z" }
  end

  before { stub_service_token }

  it "submits with the default idempotency key settlement:<reference>" do
    stub = stub_request(:post, "#{BASE_URL}/api/v1/settlements")
           .with(body: { user: "u-uuid", amount: "120", reference: "reward-42",
                         asset: "points", details: { protocol: "my-game-settlement/v1" } }.to_json,
                 headers: { "Idempotency-Key" => "settlement:reward-42" })
           .to_return(status: 202, body: settlement_json.to_json)

    settlement = client.settlements.create(user: "u-uuid", amount: "120", reference: "reward-42",
                                           details: { protocol: "my-game-settlement/v1" })
    expect(stub).to have_been_requested
    expect(settlement.state).to eq("submitted")
    expect(settlement.terminal?).to be(false)
  end

  it "fetches by reference" do
    stub_request(:get, "#{BASE_URL}/api/v1/settlements/by-reference/reward-42")
      .to_return(status: 200, body: settlement_json.merge(state: "posted").to_json)
    settlement = client.settlements.by_reference("reward-42")
    expect(settlement.state).to eq("posted")
    expect(settlement.terminal?).to be(true)
  end

  describe "#wait_for" do
    let(:no_sleep) { ->(_seconds) {} }

    it "polls until a terminal state" do
      stub = stub_request(:get, "#{BASE_URL}/api/v1/settlements/by-reference/reward-42")
             .to_return({ status: 200, body: settlement_json.to_json },
                        { status: 200, body: settlement_json.merge(state: "posted").to_json })

      settlement = client.settlements.wait_for("reward-42", timeout: 8, interval: 0.01,
                                                            sleeper: no_sleep)
      expect(settlement.state).to eq("posted")
      expect(stub).to have_been_requested.twice
    end

    it "raises RetryableError on overall timeout (result still unknown)" do
      stub_request(:get, "#{BASE_URL}/api/v1/settlements/by-reference/reward-42")
        .to_return(status: 200, body: settlement_json.to_json)
      expect do
        client.settlements.wait_for("reward-42", timeout: 0, interval: 0.01, sleeper: no_sleep)
      end.to raise_error(Sparkler::AccountCenter::RetryableError, /still submitted/)
    end
  end
end

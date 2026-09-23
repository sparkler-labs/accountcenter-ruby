# frozen_string_literal: true

RSpec.describe Sparkler::AccountCenter::Resources::Transfers do
  let(:client) do
    Sparkler::AccountCenter::Client.new(base_url: BASE_URL, client_id: "cid", client_secret: "sec")
  end

  let(:transfer_json) do
    {
      id: 12, reference: "tip:1001", asset: "points", amount: "25.5",
      from_user: "payer-uuid", to_user: "payee-uuid",
      details: { "reason" => "tip", "round" => "round-42" },
      ledger_transaction: { id: 12, reference: "tip:1001", type: "transfer", state: "posted" },
      created_at: "2026-09-20T12:00:00Z"
    }
  end

  before { stub_service_token }

  it "creates a transfer with a stable default idempotency key derived from the reference" do
    stub = stub_request(:post, "#{BASE_URL}/api/v1/transfers")
           .with(body: { from_user: "payer-uuid", to_user: "payee-uuid", amount: "25.5",
                         reference: "tip:1001", asset: "points",
                         details: { reason: "tip" } }.to_json,
                 headers: { "Idempotency-Key" => "transfer:tip:1001",
                            "Authorization" => "Bearer svc-token" })
           .to_return(status: 201, body: transfer_json.to_json)

    transfer = client.transfers.create(
      from_user: "payer-uuid", to_user: "payee-uuid", amount: "25.5",
      reference: "tip:1001", details: { reason: "tip" }
    )

    expect(stub).to have_been_requested
    expect(transfer).to be_a(Sparkler::AccountCenter::Types::Transfer)
    expect(transfer.id).to eq(12)
    expect(transfer.amount).to eq("25.5")
    expect(transfer.from_user).to eq("payer-uuid")
    expect(transfer.to_user).to eq("payee-uuid")
    expect(transfer.ledger_transaction).to be_a(Sparkler::AccountCenter::Types::LedgerTransactionSummary)
    expect(transfer.ledger_transaction.type).to eq("transfer")
    expect(transfer.ledger_transaction.state).to eq("posted")
  end

  it "omits optional asset/details and lets the caller override the idempotency key" do
    stub = stub_request(:post, "#{BASE_URL}/api/v1/transfers")
           .with(body: { from_user: "payer-uuid", to_user: "payee-uuid", amount: "1",
                         reference: "tip:1002", asset: "points" }.to_json,
                 headers: { "Idempotency-Key" => "custom-key" })
           .to_return(status: 201, body: transfer_json.merge(reference: "tip:1002").to_json)

    client.transfers.create(from_user: "payer-uuid", to_user: "payee-uuid",
                            amount: "1", reference: "tip:1002",
                            idempotency_key: "custom-key")
    expect(stub).to have_been_requested
  end

  it "fetches a transfer by id, URL-escaping the id" do
    stub = stub_request(:get, "#{BASE_URL}/api/v1/transfers/12")
           .to_return(status: 200, body: transfer_json.to_json)

    transfer = client.transfers.get(12)
    expect(stub).to have_been_requested
    expect(transfer.reference).to eq("tip:1001")
  end

  it "fetches a transfer by business reference" do
    stub = stub_request(:get, "#{BASE_URL}/api/v1/transfers/by-reference/tip%3A1001")
           .to_return(status: 200, body: transfer_json.to_json)

    transfer = client.transfers.by_reference("tip:1001")
    expect(stub).to have_been_requested
    expect(transfer.id).to eq(12)
  end

  it "maps 409 idempotency_conflict to a deterministic error" do
    stub_request(:post, "#{BASE_URL}/api/v1/transfers")
      .to_return(status: 409, body: { error: "idempotency_conflict" }.to_json)

    expect do
      client.transfers.create(from_user: "a", to_user: "b", amount: "1", reference: "r")
    end.to raise_error(Sparkler::AccountCenter::DeterministicError) { |e|
      expect(e.code).to eq("idempotency_conflict")
      expect(e.status).to eq(409)
    }
  end

  it "maps 402 insufficient_funds to a deterministic error" do
    stub_request(:post, "#{BASE_URL}/api/v1/transfers")
      .to_return(status: 402, body: { error: "insufficient_funds" }.to_json)

    expect do
      client.transfers.create(from_user: "a", to_user: "b", amount: "1", reference: "r")
    end.to raise_error(Sparkler::AccountCenter::DeterministicError) { |e|
      expect(e.code).to eq("insufficient_funds")
      expect(e.status).to eq(402)
    }
  end
end

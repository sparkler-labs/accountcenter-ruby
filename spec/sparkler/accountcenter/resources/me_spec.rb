# frozen_string_literal: true

RSpec.describe Sparkler::AccountCenter::Resources::Me do
  let(:client) do
    Sparkler::AccountCenter::Client.new(base_url: BASE_URL, bearer_token: "user-jwt")
  end

  describe "#ledger_entries" do
    let(:response_json) do
      {
        entries: [
          {
            id: 101, asset: "points", amount: "-30.0", balance_after: "70.0",
            created_at: "2026-09-20T12:00:00Z",
            ledger_transaction: { id: 9, type: "withdrawal", reference: "wd:20260919-1" }
          },
          {
            id: 100, asset: "points", amount: "100.0", balance_after: "100.0",
            created_at: "2026-09-20T11:00:00Z",
            ledger_transaction: { id: 8, type: "deposit", reference: "dep:1" }
          }
        ],
        meta: { page: 1, per_page: 20, total: 2 }
      }
    end

    it "queries the current user's ledger entries with default pagination" do
      stub = stub_request(:get, "#{BASE_URL}/api/v1/me/ledger_entries")
             .with(query: { asset: "points", page: "1", per_page: "20" },
                   headers: { "Authorization" => "Bearer user-jwt" })
             .to_return(status: 200, body: response_json.to_json)

      result = client.me.ledger_entries

      expect(stub).to have_been_requested
      expect(result["entries"].size).to eq(2)
      expect(result["entries"].first["amount"]).to eq("-30.0")
      expect(result["meta"]).to eq("page" => 1, "per_page" => 20, "total" => 2)
    end

    it "passes through asset, page and per_page" do
      stub = stub_request(:get, "#{BASE_URL}/api/v1/me/ledger_entries")
             .with(query: { asset: "game_a_points", page: "3", per_page: "50" })
             .to_return(status: 200, body: { entries: [], meta: { page: 3, per_page: 50, total: 0 } }.to_json)

      client.me.ledger_entries(asset: "game_a_points", page: 3, per_page: 50)
      expect(stub).to have_been_requested
    end
  end
end

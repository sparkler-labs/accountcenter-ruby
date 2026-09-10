# frozen_string_literal: true

RSpec.describe Sparkler::AccountCenter::Resources::Balances do
  let(:client) do
    Sparkler::AccountCenter::Client.new(base_url: BASE_URL, client_id: "cid", client_secret: "sec")
  end

  before { stub_service_token }

  it "fetches a single batch as a player => decimal-string hash" do
    stub_request(:get, "#{BASE_URL}/api/v1/balances")
      .with(query: { players: "a,b" })
      .to_return(status: 200, body: { balances: { "a" => "10.5", "b" => "0" } }.to_json)
    expect(client.balances.get(%w[a b])).to eq("a" => "10.5", "b" => "0")
  end

  it "slices players into batches of 100 and merges the results" do
    players = (1..250).map { |i| "p#{i}" }
    [players.first(100), players[100, 100], players.last(50)].each do |batch|
      stub_request(:get, "#{BASE_URL}/api/v1/balances")
        .with(query: { players: batch.join(",") })
        .to_return(status: 200, body: { balances: batch.to_h { |p| [p, "1"] } }.to_json)
    end

    result = client.balances.get(players)
    expect(result.size).to eq(250)
    expect(result["p1"]).to eq("1")
    expect(result["p250"]).to eq("1")
  end

  it "returns an empty hash for no players without calling the platform" do
    expect(client.balances.get([])).to eq({})
  end
end

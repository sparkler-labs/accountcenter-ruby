# frozen_string_literal: true

RSpec.describe "SIWE challenge contract" do
  let(:public_client) { Sparkler::AccountCenter::Client.new(base_url: BASE_URL) }
  let(:user_client) { Sparkler::AccountCenter::Client.new(base_url: BASE_URL, bearer_token: "user-jwt") }

  it "challenge passes address and chain_id as query params" do
    stub = stub_request(:get, "#{BASE_URL}/api/v1/game_tokens/new")
           .with(query: { address: "0xabc", chain_id: "84532" })
           .to_return(status: 200, body: { message: "siwe text", ticket: "opaque-ticket" }.to_json)
    challenge = public_client.game_tokens.challenge(address: "0xabc", chain_id: 84_532)
    expect(stub).to have_been_requested
    expect(challenge).to eq("message" => "siwe text", "ticket" => "opaque-ticket")
  end

  it "create_with_siwe submits the opaque ticket (not the message) plus signature" do
    stub = stub_request(:post, "#{BASE_URL}/api/v1/game_tokens")
           .with(body: { ticket: "opaque-ticket", signature: "0xsig" }.to_json)
           .to_return(status: 200, body: { ticket: "rs256-jwt" }.to_json)
    result = public_client.game_tokens.create_with_siwe(ticket: "opaque-ticket", signature: "0xsig")
    expect(stub).to have_been_requested
    expect(result["ticket"]).to eq("rs256-jwt")
  end

  it "auth.wallet submits { ticket, signature }" do
    stub = stub_request(:post, "#{BASE_URL}/api/v1/auth/wallet")
           .with(body: { ticket: "opaque-ticket", signature: "0xsig" }.to_json)
           .to_return(status: 200, body: { token: "jwt", user: { id: 1 }, game_token: "t" }.to_json)
    public_client.auth.wallet(ticket: "opaque-ticket", signature: "0xsig")
    expect(stub).to have_been_requested
  end

  it "me.create_address submits { ticket, signature } with the user Bearer token" do
    stub = stub_request(:post, "#{BASE_URL}/api/v1/me/addresses")
           .with(body: { ticket: "opaque-ticket", signature: "0xsig" }.to_json,
                 headers: { "Authorization" => "Bearer user-jwt" })
           .to_return(status: 201, body: { id: 3, address: "0xabc" }.to_json)
    user_client.me.create_address(ticket: "opaque-ticket", signature: "0xsig")
    expect(stub).to have_been_requested
  end
end

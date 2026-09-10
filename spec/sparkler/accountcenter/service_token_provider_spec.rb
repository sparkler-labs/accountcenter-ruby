# frozen_string_literal: true

RSpec.describe Sparkler::AccountCenter::ServiceTokenProvider do
  let(:http) { Sparkler::AccountCenter::Http.new(base_url: BASE_URL) }

  def provider(expiry_margin: 60)
    described_class.new(http: http, client_id: "cid", client_secret: "sec",
                        scope: "funds", expiry_margin: expiry_margin)
  end

  it "caches the token across calls" do
    token_stub = stub_service_token
    p = provider
    expect(p.token).to eq("svc-token")
    expect(p.token).to eq("svc-token")
    expect(token_stub).to have_been_requested.once
  end

  it "refreshes when the cached token is inside the early-expiry margin" do
    token_stub = stub_service_token(expires_in: 30) # < 60s margin → immediately stale
    p = provider
    p.token
    p.token
    expect(token_stub).to have_been_requested.twice
  end

  it "refetches after reset!" do
    token_stub = stub_service_token
    p = provider
    p.token
    p.reset!
    p.token
    expect(token_stub).to have_been_requested.twice
  end

  it "raises RetryableError when the token response lacks access_token" do
    stub_request(:post, "#{BASE_URL}/oauth/token")
      .to_return(status: 200, body: { token_type: "Bearer" }.to_json)
    expect { provider.token }.to raise_error(Sparkler::AccountCenter::RetryableError)
  end
end

RSpec.describe "service client 401 handling" do
  let(:client) do
    Sparkler::AccountCenter::Client.new(base_url: BASE_URL, client_id: "cid", client_secret: "sec")
  end

  it "clears the token cache and retries the request once on 401" do
    token_stub = stub_service_token
    hold_stub = stub_request(:get, "#{BASE_URL}/api/v1/holds/7")
                .to_return({ status: 401, body: { error: "unauthorized" }.to_json },
                           { status: 200, body: { id: 7, state: "reserved", asset: "points",
                                                  amount: "50", action_id: "a1", account_id: 1,
                                                  user: "u-1", expires_at: "t", executed_at: nil,
                                                  captured_at: nil, released_at: nil,
                                                  created_at: "t" }.to_json })

    hold = client.holds.get(7)
    expect(hold.id).to eq(7)
    expect(token_stub).to have_been_requested.twice
    expect(hold_stub).to have_been_requested.twice
  end

  it "does not retry when the 401 persists" do
    stub_service_token
    hold_stub = stub_request(:get, "#{BASE_URL}/api/v1/holds/7")
                .to_return(status: 401, body: { error: "unauthorized" }.to_json)
    expect { client.holds.get(7) }
      .to raise_error(Sparkler::AccountCenter::DeterministicError) { |e| expect(e.status).to eq(401) }
    expect(hold_stub).to have_been_requested.twice # initial + single 401 retry
  end
end

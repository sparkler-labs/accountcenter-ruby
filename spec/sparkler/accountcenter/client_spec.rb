# frozen_string_literal: true

RSpec.describe Sparkler::AccountCenter::Client do
  describe "credential modes" do
    it "requires client_id and client_secret together" do
      expect { described_class.new(base_url: BASE_URL, client_id: "cid") }
        .to raise_error(ArgumentError, /together/)
    end

    it "rejects bearer_token combined with client credentials" do
      expect do
        described_class.new(base_url: BASE_URL, client_id: "cid", client_secret: "sec",
                            bearer_token: "tok")
      end.to raise_error(ArgumentError, /mutually exclusive/)
    end

    it "strips a trailing slash from base_url" do
      client = described_class.new(base_url: "#{BASE_URL}/")
      expect(client.base_url).to eq(BASE_URL)
    end
  end

  describe "bearer mode" do
    it "attaches the static bearer token and never calls the token endpoint" do
      client = described_class.new(base_url: BASE_URL, bearer_token: "user-jwt")
      stub = stub_request(:get, "#{BASE_URL}/api/v1/me")
             .with(headers: { "Authorization" => "Bearer user-jwt" })
             .to_return(status: 200, body: { id: 1 }.to_json)
      expect(client.me.get).to eq("id" => 1)
      expect(stub).to have_been_requested
    end
  end

  describe "automatic retries" do
    let(:client) do
      described_class.new(base_url: BASE_URL, client_id: "cid", client_secret: "sec",
                          retry_options: { sleeper: ->(_s) {} })
    end

    before { stub_service_token }

    it "retries 5xx with the same idempotency key until success" do
      hold_json = { id: 1, state: "reserved", asset: "points", amount: "50",
                    action_id: "a1", account_id: 1, user: "u", expires_at: "t",
                    executed_at: nil, captured_at: nil, released_at: nil, created_at: "t" }
      stub = stub_request(:post, "#{BASE_URL}/api/v1/holds")
             .with(headers: { "Idempotency-Key" => "a1" })
             .to_return({ status: 500, body: "" },
                        { status: 201, body: hold_json.to_json })
      hold = client.holds.create(user: "u", amount: "50", action_id: "a1")
      expect(hold.id).to eq(1)
      expect(stub).to have_been_requested.twice
    end

    it "never retries deterministic errors" do
      stub = stub_request(:post, "#{BASE_URL}/api/v1/holds")
             .to_return(status: 422, body: { error: "invalid_amount" }.to_json)
      expect { client.holds.create(user: "u", amount: "-5", action_id: "a1") }
        .to raise_error(Sparkler::AccountCenter::DeterministicError)
      expect(stub).to have_been_requested.once
    end

    it "can be disabled with retry_options: false" do
      no_retry = described_class.new(base_url: BASE_URL, client_id: "cid", client_secret: "sec",
                                     retry_options: false)
      stub = stub_request(:post, "#{BASE_URL}/api/v1/holds").to_return(status: 500, body: "")
      expect { no_retry.holds.create(user: "u", amount: "50", action_id: "a1") }
        .to raise_error(Sparkler::AccountCenter::RetryableError)
      expect(stub).to have_been_requested.once
    end
  end

  describe "public (no credentials) mode" do
    it "issues guest tickets without authentication" do
      client = described_class.new(base_url: BASE_URL)
      stub = stub_request(:post, "#{BASE_URL}/api/v1/game_tokens/guest")
             .to_return(status: 200, body: { ticket: "t", guest_token: "g",
                                             player_id: "user:9", nickname: "Swift Fox #4821" }.to_json)
      guest = client.game_tokens.guest
      expect(stub).to have_been_requested
      expect(guest.guest_token).to eq("g")
      expect(guest.player_id).to eq("user:9")
    end
  end
end

# frozen_string_literal: true

RSpec.describe Sparkler::AccountCenter::Http do
  subject(:http) { described_class.new(base_url: BASE_URL) }

  it "sends JSON bodies and parses JSON responses" do
    stub = stub_request(:post, "#{BASE_URL}/api/v1/things")
           .with(body: { a: 1 }.to_json)
           .to_return(status: 200, body: { ok: true }.to_json,
                      headers: { "Content-Type" => "application/json" })
    expect(http.request(:post, "/api/v1/things", body: { a: 1 })).to eq("ok" => true)
    expect(stub).to have_been_requested
  end

  it "encodes query params" do
    stub_request(:get, "#{BASE_URL}/api/v1/balances")
      .with(query: { players: "a,b" })
      .to_return(status: 200, body: { balances: { a: "0", b: "1" } }.to_json)
    expect(http.request(:get, "/api/v1/balances", query: { players: "a,b" }))
      .to eq("balances" => { "a" => "0", "b" => "1" })
  end

  it "returns nil for empty and non-JSON success bodies" do
    stub_request(:get, "#{BASE_URL}/empty").to_return(status: 204)
    stub_request(:get, "#{BASE_URL}/html").to_return(status: 200, body: "<html>")
    expect(http.request(:get, "/empty")).to be_nil
    expect(http.request(:get, "/html")).to be_nil
  end

  describe "error body parsing" do
    it "extracts a string error code" do
      stub_request(:get, "#{BASE_URL}/x")
        .to_return(status: 422, body: { error: "invalid_amount" }.to_json)
      expect { http.request(:get, "/x") }
        .to raise_error(Sparkler::AccountCenter::DeterministicError) { |e| expect(e.code).to eq("invalid_amount") }
    end

    it "tolerates array error bodies (user endpoints) and keeps the first message" do
      stub_request(:get, "#{BASE_URL}/x")
        .to_return(status: 422, body: { error: ["Username can't be blank"] }.to_json)
      expect { http.request(:get, "/x") }
        .to raise_error(Sparkler::AccountCenter::DeterministicError) { |e|
          expect(e.code).to eq("Username can't be blank")
        }
    end

    it "tolerates empty and non-JSON error bodies (code nil, still classified)" do
      stub_request(:get, "#{BASE_URL}/x").to_return(status: 500, body: "")
      expect { http.request(:get, "/x") }
        .to raise_error(Sparkler::AccountCenter::RetryableError) { |e|
          expect(e.code).to be_nil
          expect(e.status).to eq(500)
        }
    end
  end

  it "wraps connection failures into RetryableError" do
    stub_request(:get, "#{BASE_URL}/x").to_raise(Errno::ECONNREFUSED)
    expect { http.request(:get, "/x") }
      .to raise_error(Sparkler::AccountCenter::RetryableError) { |e| expect(e.status).to be_nil }
  end

  it "wraps timeouts into RetryableError" do
    stub_request(:get, "#{BASE_URL}/x").to_timeout
    expect { http.request(:get, "/x") }.to raise_error(Sparkler::AccountCenter::RetryableError)
  end
end

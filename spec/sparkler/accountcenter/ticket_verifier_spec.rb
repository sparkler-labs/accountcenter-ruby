# frozen_string_literal: true

require "openssl"
require "base64"
require "json"

RSpec.describe Sparkler::AccountCenter::TicketVerifier do
  let(:rsa) { OpenSSL::PKey::RSA.generate(2048) }
  let(:kid) { "testkid01" }
  let(:jwks_url) { "#{BASE_URL}/api/v1/game/jwks.json" }
  let(:issuer) { "https://accountcenter.example" }
  let(:audience) { "minesweeper" }

  subject(:verifier) { described_class.new(jwks_url: jwks_url, issuer: issuer, audience: audience) }

  def jwk_for(key)
    {
      kty: "RSA", use: "sig", kid: kid,
      n: Base64.urlsafe_encode64(key.n.to_s(2), padding: false),
      e: Base64.urlsafe_encode64(key.e.to_s(2), padding: false)
    }
  end

  def stub_jwks(keys: [jwk_for(rsa)], status: 200)
    stub_request(:get, jwks_url)
      .to_return(status: status, body: { keys: keys }.to_json,
                 headers: { "Content-Type" => "application/json" })
  end

  def encode_part(hash)
    Base64.urlsafe_encode64(JSON.generate(hash), padding: false)
  end

  def sign_ticket(key, claims, header_kid: kid)
    header = encode_part({ alg: "RS256", typ: "JWT", kid: header_kid })
    payload = encode_part(claims)
    signature = Base64.urlsafe_encode64(
      key.sign(OpenSSL::Digest.new("SHA256"), "#{header}.#{payload}"), padding: false
    )
    "#{header}.#{payload}.#{signature}"
  end

  def valid_claims(**overrides)
    now = Time.now.to_i
    {
      iss: issuer, sub: "user-uuid-1", aud: audience, iat: now, exp: now + 60,
      jti: "jti-#{SecureRandom.hex(4)}", session_id: "sess-1",
      address: "0xabc", player_id: "user:1", nickname: "Swift Fox #4821",
      flag_style: "red", balance: "120.5"
    }.merge(overrides)
  end

  it "verifies a well-formed ticket and returns its claims" do
    stub_jwks
    claims = verifier.verify!(sign_ticket(rsa, valid_claims(jti: "jti-ok")))
    expect(claims).to be_a(Sparkler::AccountCenter::Types::TicketClaims)
    expect(claims.sub).to eq("user-uuid-1")
    expect(claims.player_id).to eq("user:1")
    expect(claims.balance).to eq("120.5")
  end

  it "caches JWKS across verifications" do
    jwks_stub = stub_jwks
    verifier.verify!(sign_ticket(rsa, valid_claims))
    verifier.verify!(sign_ticket(rsa, valid_claims))
    expect(jwks_stub).to have_been_requested.once
  end

  it "rejects expired tickets" do
    stub_jwks
    expired = valid_claims(exp: Time.now.to_i - 1)
    expect { verifier.verify!(sign_ticket(rsa, expired)) }
      .to raise_error(Sparkler::AccountCenter::TicketError, /expired/)
  end

  it "rejects tickets with the wrong audience" do
    stub_jwks
    expect { verifier.verify!(sign_ticket(rsa, valid_claims(aud: "other-game"))) }
      .to raise_error(Sparkler::AccountCenter::TicketError, /aud/)
  end

  it "rejects tickets with the wrong issuer" do
    stub_jwks
    expect { verifier.verify!(sign_ticket(rsa, valid_claims(iss: "https://evil.example"))) }
      .to raise_error(Sparkler::AccountCenter::TicketError, /iss/)
  end

  it "rejects a replayed jti" do
    stub_jwks
    ticket = sign_ticket(rsa, valid_claims(jti: "jti-replay"))
    verifier.verify!(ticket)
    expect { verifier.verify!(ticket) }
      .to raise_error(Sparkler::AccountCenter::TicketError, /replay/)
  end

  it "rejects signatures from a different key" do
    stub_jwks
    other = OpenSSL::PKey::RSA.generate(2048)
    expect { verifier.verify!(sign_ticket(other, valid_claims)) }
      .to raise_error(Sparkler::AccountCenter::TicketError, /signature/)
  end

  it "rejects tickets whose kid has no matching JWKS key" do
    stub_jwks
    expect { verifier.verify!(sign_ticket(rsa, valid_claims, header_kid: "unknown")) }
      .to raise_error(Sparkler::AccountCenter::TicketError, /no signing key/)
  end

  it "rejects malformed tickets" do
    expect { verifier.verify!("not-a-jwt") }
      .to raise_error(Sparkler::AccountCenter::TicketError, /malformed/)
  end

  it "fails closed when JWKS cannot be fetched and no cache exists" do
    jwks_stub = stub_jwks(status: 500)
    expect { verifier.verify!(sign_ticket(rsa, valid_claims)) }
      .to raise_error(Sparkler::AccountCenter::TicketError, /JWKS/)

    # Inside the 30s failure backoff window: no repeat fetch, still fail-closed
    expect { verifier.verify!(sign_ticket(rsa, valid_claims)) }
      .to raise_error(Sparkler::AccountCenter::TicketError, /JWKS/)
    expect(jwks_stub).to have_been_requested.once
  end

  it "serves the stale cache when a refetch fails inside the backoff window" do
    ttl0 = described_class.new(jwks_url: jwks_url, issuer: issuer, audience: audience, jwks_ttl: 0)
    ok = { status: 200, body: { keys: [jwk_for(rsa)] }.to_json,
           headers: { "Content-Type" => "application/json" } }
    jwks_stub = stub_request(:get, jwks_url).to_return(ok, { status: 500, body: "" })

    ttl0.verify!(sign_ticket(rsa, valid_claims)) # warm the cache
    # jwks_ttl: 0 forces a refetch; the 500 lands in the backoff window → stale cache
    claims = ttl0.verify!(sign_ticket(rsa, valid_claims))
    expect(claims.sub).to eq("user-uuid-1")
    expect(jwks_stub).to have_been_requested.twice
  end
end

# frozen_string_literal: true

require "webmock/rspec"
require "securerandom"
require "sparkler/accountcenter"

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.expect_with :rspec do |expectations|
    expectations.syntax = :expect
  end
  config.order = :random
  Kernel.srand config.seed
end

BASE_URL = "http://platform.test"

# Stubs the client_credentials token endpoint with a fresh token.
def stub_service_token(access_token: "svc-token", expires_in: 300)
  stub_request(:post, "#{BASE_URL}/oauth/token")
    .with(body: { grant_type: "client_credentials", client_id: "cid",
                  client_secret: "sec", scope: "funds" }.to_json)
    .to_return(status: 200,
               body: { access_token: access_token, token_type: "Bearer", expires_in: expires_in }.to_json,
               headers: { "Content-Type" => "application/json" })
end

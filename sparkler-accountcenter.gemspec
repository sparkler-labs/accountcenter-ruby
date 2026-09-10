# frozen_string_literal: true

require_relative "lib/sparkler/accountcenter/version"

Gem::Specification.new do |spec|
  spec.name = "sparkler-accountcenter"
  spec.version = Sparkler::AccountCenter::VERSION
  spec.authors = ["SparklerDAO"]
  spec.summary = "Official Ruby SDK for the Sparkler AccountCenter platform"
  spec.description = "Thin Ruby client for the Sparkler AccountCenter public game platform: " \
                     "service funds APIs (holds/settlements/balances), user APIs, webhook " \
                     "signature verification and RS256 game ticket verification. " \
                     "Zero runtime dependencies (stdlib only: net/http, json, openssl)."
  spec.homepage = "https://github.com/sparklerdao/minesweeper"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.files = Dir["lib/**/*", "README.md"]
  spec.require_paths = ["lib"]

  spec.metadata = {
    "source_code_uri" => spec.homepage,
    "rubygems_mfa_required" => "true"
  }

  spec.add_dependency "base64", ">= 0.2" # bundled gem since Ruby 3.4 (stdlib before)

  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.13"
  spec.add_development_dependency "rubocop", "~> 1.60"
  spec.add_development_dependency "webmock", "~> 3.23"
end

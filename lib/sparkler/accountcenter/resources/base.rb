# frozen_string_literal: true

module Sparkler
  module AccountCenter
    module Resources
      # Shared plumbing for resource classes: thin wrappers over Client#request.
      # Helpers are named request_* so resources can freely define their own
      # get/create/list methods without dispatch ambiguity.
      class Base
        def initialize(client)
          @client = client
        end

        private

        def request_get(path, query: nil, bearer: nil)
          @client.request(:get, path, query: query, bearer: bearer)
        end

        def request_post(path, body: nil, idempotency_key: nil, bearer: nil)
          @client.request(:post, path, body: body, idempotency_key: idempotency_key, bearer: bearer)
        end

        def request_patch(path, body: nil, bearer: nil)
          @client.request(:patch, path, body: body, bearer: bearer)
        end

        def request_delete(path, bearer: nil)
          @client.request(:delete, path, bearer: bearer)
        end
      end
    end
  end
end

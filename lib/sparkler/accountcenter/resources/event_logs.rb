# frozen_string_literal: true

require "uri"

module Sparkler
  module AccountCenter
    module Resources
      # Game round event logs (Bearer user JWT). Responses are raw parsed JSON.
      class EventLogs < Base
        # GET /api/v1/rounds/:round_id/event_logs
        def list(round_id)
          request_get("/api/v1/rounds/#{URI.encode_www_form_component(round_id.to_s)}/event_logs")
        end
      end
    end
  end
end

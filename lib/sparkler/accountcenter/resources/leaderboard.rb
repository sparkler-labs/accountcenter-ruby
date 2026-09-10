# frozen_string_literal: true

module Sparkler
  module AccountCenter
    module Resources
      # Public leaderboard (no authentication).
      class Leaderboard < Base
        # GET /api/v1/leaderboard
        def get(query = nil)
          request_get("/api/v1/leaderboard", query: query)
        end
      end
    end
  end
end

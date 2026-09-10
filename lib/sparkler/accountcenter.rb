# frozen_string_literal: true

require_relative "accountcenter/version"
require_relative "accountcenter/errors"
require_relative "accountcenter/retry"
require_relative "accountcenter/http"
require_relative "accountcenter/service_token_provider"
require_relative "accountcenter/types"
require_relative "accountcenter/webhook_verifier"
require_relative "accountcenter/ticket_verifier"
require_relative "accountcenter/resources/base"
require_relative "accountcenter/resources/auth"
require_relative "accountcenter/resources/game_tokens"
require_relative "accountcenter/resources/me"
require_relative "accountcenter/resources/withdrawals"
require_relative "accountcenter/resources/leaderboard"
require_relative "accountcenter/resources/event_logs"
require_relative "accountcenter/resources/holds"
require_relative "accountcenter/resources/settlements"
require_relative "accountcenter/resources/balances"
require_relative "accountcenter/client"

# Official Ruby SDK for the Sparkler AccountCenter public game platform.
module Sparkler
  module AccountCenter
  end
end

# typed: strict
# frozen_string_literal: true

module Services
  module Inbound
    class HistoryRecovery
      # History reached the upstream cap; the checkpoint stays and an operator must recover.
      class RecoveryRequired < Adapters::Mattermost::Errors::RequestFailed; end
    end
  end
end

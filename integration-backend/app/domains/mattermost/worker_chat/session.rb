# typed: strict
# frozen_string_literal: true

module Domains
  module Mattermost
    class WorkerChat
      class Session < T::Struct
        const :id, String
        const :workflow_id, String
        const :role, String
        const :generation, Integer
        const :credential_expires_at, Time
      end
    end
  end
end

# typed: strict
# frozen_string_literal: true

module Domains
  module Workflows
    module Dto
      # One recorded human approval of an exact artifact commit.
      class ApprovalView < T::Struct
        include Kirei::Domain::ValueObject

        const :id, Integer
        const :workflow_id, String
        const :gate, Gate
        const :target_commit, String
        const :user_id, String
        const :channel_id, String
        const :post_id, String
        const :created_at, Time
      end
    end
  end
end

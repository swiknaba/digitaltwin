# typed: strict
# frozen_string_literal: true

module Domains
  module Commander
    module Dto
      # One human follow-up instruction routed to a workflow's Writer session.
      class FollowupView < T::Struct
        include Kirei::Domain::ValueObject

        const :id, String
        const :inbox_id, String
        const :workflow_id, String
        const :session_id, T.nilable(String)
        const :generation, T.nilable(Integer)
        const :status, FollowupStatus
        const :reason, T.nilable(String)
        const :evidence, RoutingEvidence
        const :created_at, Time
        const :delivered_at, T.nilable(Time)
      end
    end
  end
end

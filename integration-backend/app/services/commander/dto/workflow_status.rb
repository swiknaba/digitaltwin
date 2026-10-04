# typed: strict
# frozen_string_literal: true

module Services
  module Commander
    module Dto
      # A durable, visibility-filtered description of one workflow for Commander.
      class WorkflowStatus < T::Struct
        include Kirei::Domain::ValueObject

        const :project_id, String
        const :project_slug, String
        const :workflow_id, String
        const :thread_id, String
        const :phase, String
        const :wait_reason, T.nilable(String)
        const :session_state, T.nilable(String)
        const :last_verified_at, T.nilable(Time)
        const :review_state, T.nilable(String)
        const :approval_state, T.nilable(String)
        const :delivery_state, T.nilable(String)
        const :artifact_links, T::Array[String]
      end
    end
  end
end

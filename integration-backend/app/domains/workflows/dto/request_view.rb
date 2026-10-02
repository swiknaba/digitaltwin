# typed: strict
# frozen_string_literal: true

module Domains
  module Workflows
    module Dto
      # One `workflow_requests` row: a verified human start and its progress.
      class RequestView < T::Struct
        include Kirei::Domain::ValueObject

        const :id, String
        const :inbox_id, Integer
        const :project_id, String
        const :workflow_id, T.nilable(String)
        const :request_digest, String
        const :parameters, RequestParameters
        const :state, RequestState
        const :thread_id, T.nilable(String)
        const :reason, T.nilable(String)
        const :created_at, Time
      end
    end
  end
end

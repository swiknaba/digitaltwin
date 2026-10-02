# typed: strict
# frozen_string_literal: true

# == Schema Info
#
# Table name: workflow_requests
#
#  id                  :text                not null, primary key
#  inbox_id            :integer             not null
#  project_id          :text                not null
#  workflow_id         :text                null
#  request_digest      :text                not null
#  parameters          :jsonb               not null
#  state               :text                not null
#  thread_id           :text                null
#  reason              :text                null
#  created_at          :timestamp without time zone, not null
#

module Domains
  module Workflows
    module Entities
      class WorkflowRequest < T::Struct
        include Kirei::Model
        include Kirei::Domain::Entity

        const :id, String
        const :inbox_id, Integer
        const :project_id, String
        const :workflow_id, T.nilable(String)
        const :request_digest, String
        const :parameters, Dto::RequestParameters
        const :state, Dto::RequestState
        const :thread_id, T.nilable(String)
        const :reason, T.nilable(String)
        const :created_at, Time
      end
    end
  end
end

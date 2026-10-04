# typed: strict
# frozen_string_literal: true

module Domains
  module Sessions
    module Dto
      # One agent session. `workflow_id` is nil only for the commander.
      class SessionView < T::Struct
        include Kirei::Domain::ValueObject

        const :id, String
        const :workflow_id, T.nilable(String)
        const :role, SessionRole
        const :generation, Integer
        const :pane_id, String
        const :alias, String
        const :configuration, Workflows::Dto::RoleConfig
        const :credential_digest, String
        const :credential_expires_at, Time
        const :active, T::Boolean
        const :last_verified_at, T.nilable(Time)
        const :state, SessionState
        const :runtime_identity, T.nilable(RuntimeIdentity)
        const :workspace_id, T.nilable(String)
        const :created_at, Time
      end
    end
  end
end

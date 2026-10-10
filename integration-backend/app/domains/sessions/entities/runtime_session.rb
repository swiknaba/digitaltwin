# typed: strict
# frozen_string_literal: true

# == Schema Info
#
# Table name: sessions
#
#  id                  :text                not null, primary key
#  workflow_id         :text                null
#  role                :text                not null
#  generation          :integer             not null
#  pane_id             :text                not null
#  alias               :text                not null
#  configuration       :jsonb               not null
#  credential_digest   :text                not null
#  credential_expires_at:timestamp without time zone, not null
#  active              :boolean             not null
#  last_verified_at    :timestamp without time zone, null
#  state               :text                not null
#  created_at          :timestamp without time zone, not null
#  runtime_identity    :jsonb               null
#  workspace_id        :text                null
#

module Domains
  module Sessions
    module Entities
      class RuntimeSession < T::Struct
        extend T::Sig
        include Kirei::Model
        include Kirei::Domain::Entity

        sig { override.returns(Integer) }
        def self.human_id_length = 12

        # The table and chat messages call these "sessions"; the class name avoids a clash with the domain module.
        sig { override.returns(String) }
        def self.human_id_prefix = "session"

        sig { override.returns(String) }
        def self.table_name = "sessions"

        const :id, String
        const :workflow_id, T.nilable(String)
        const :role, Dto::SessionRole
        const :generation, Integer
        const :pane_id, String
        const :alias, String
        const :configuration, Workflows::Dto::RoleConfig
        const :credential_digest, String
        const :credential_expires_at, Time
        const :active, T::Boolean, default: true
        const :last_verified_at, T.nilable(Time), default: nil
        const :state, Dto::SessionState, default: Dto::SessionState::Unknown
        const :runtime_identity, T.nilable(Dto::RuntimeIdentity), default: nil
        const :workspace_id, T.nilable(String), default: nil
        const :created_at, Time, factory: -> { Time.now.utc }
      end
    end
  end
end

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
#  runtime_identity    :jsonb               null
#  workspace_id        :text                null
#

module Domains
  module Sessions
    class RuntimeSession < T::Struct
      extend T::Sig
      include Kirei::Model

      Configuration = T.type_alias { T::Hash[String, Object] }

      sig { override.returns(String) }
      def self.table_name = "sessions"

      const :id, String
      const :workflow_id, T.nilable(String)
      const :role, String
      const :generation, Integer
      const :pane_id, String
      const :alias, String
      const :configuration, Configuration
      const :credential_digest, String
      const :credential_expires_at, Time
      const :active, T::Boolean, default: true
      const :last_verified_at, T.nilable(Time), default: nil
      const :state, String, default: "unknown"
      const :runtime_identity, T.nilable(Configuration), default: nil
      const :workspace_id, T.nilable(String), default: nil
    end
  end
end

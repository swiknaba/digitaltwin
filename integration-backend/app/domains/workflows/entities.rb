# typed: strict
# frozen_string_literal: true

module Domains
  module Workflows
    module Entities
      class Actor < T::Struct
        const :user_id, String
        const :channel_id, String
        const :member, T::Boolean
        const :bot, T::Boolean
      end

      class RoleConfig < T::Struct
        const :cli, String
        const :provider, String
        const :model, String
        const :family, String
      end

      class ArtifactRef < T::Struct
        const :kind, String
        const :commit, String
        const :path, T.nilable(String)
      end

      class SessionRef < T::Struct
        const :workflow_id, T.nilable(String)
        const :generation, Integer
        const :role, String
        const :pane_id, String
        const :alias, String
      end

      class Outcome < T::Struct
        const :status, String
        const :reason, String
        const :links, T::Array[String], default: []
      end
    end
  end
end

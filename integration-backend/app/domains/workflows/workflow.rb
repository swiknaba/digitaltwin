# typed: strict
# frozen_string_literal: true

module Domains
  module Workflows
    class Workflow < T::Struct
      include Kirei::Model

      JsonObject = T.type_alias { T::Hash[String, Object] }

      const :id, String
      const :project_id, String
      const :channel_id, String
      const :thread_id, String
      const :branch, String
      const :worktree_path, String
      const :phase, String, default: "spec_writing"
      const :saved_phase, T.nilable(String), default: nil
      const :version, Integer, default: 0
      const :artifacts, JsonObject, default: {}
      const :blocker, T.nilable(String), default: nil
      const :archived_at, T.nilable(Time), default: nil
      const :created_at, Time, factory: -> { Time.now.utc }
      const :paused_commit, T.nilable(String), default: nil
      const :source_inbox_id, T.nilable(Integer), default: nil
      const :role_configurations, JsonObject, default: {}
    end
  end
end

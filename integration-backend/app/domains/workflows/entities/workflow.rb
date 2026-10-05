# typed: strict
# frozen_string_literal: true

# == Schema Info
#
# Table name: workflows
#
#  id                  :text                not null, primary key
#  project_id          :text                not null
#  channel_id          :text                not null
#  thread_id           :text                not null
#  branch              :text                not null
#  worktree_path       :text                not null
#  phase               :text                not null
#  saved_phase         :text                null
#  version             :integer             not null
#  artifacts           :jsonb               not null
#  blocker             :text                null
#  archived_at         :timestamp without time zone, null
#  created_at          :timestamp without time zone, not null
#  paused_commit       :text                null
#  source_inbox_id     :text                null
#  role_configurations :jsonb               not null
#

module Domains
  module Workflows
    module Entities
      class Workflow < T::Struct
        extend T::Sig
        include Kirei::Model
        include Kirei::Domain::Entity

        # Workflow ids are typed by humans in approve/route commands and name branches and worktrees.
        sig { override.returns(Integer) }
        def self.human_id_length = 12

        const :id, String
        const :project_id, String
        const :channel_id, String
        const :thread_id, String
        const :branch, String
        const :worktree_path, String
        # Defaults match the column defaults, so `create` needs only the binding fields.
        const :phase, Dto::Phase, default: Dto::Phase::SpecWriting
        const :saved_phase, T.nilable(Dto::Phase), default: nil
        const :version, Integer, default: 0
        const :artifacts, Dto::ArtifactSet, factory: -> { Dto::ArtifactSet.new }
        const :blocker, T.nilable(String), default: nil
        const :archived_at, T.nilable(Time), default: nil
        const :created_at, Time, factory: -> { Time.now.utc }
        const :paused_commit, T.nilable(String), default: nil
        const :source_inbox_id, T.nilable(String), default: nil
        const :role_configurations, Dto::RoleAssignments
      end
    end
  end
end

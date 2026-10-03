# typed: strict
# frozen_string_literal: true

Sequel.migration do
  change do
    create_table(:workflows) do
      String :id, primary_key: true
      foreign_key :project_id, :projects, type: String, null: false
      String :channel_id, null: false
      String :thread_id, null: false
      String :branch, null: false, unique: true
      String :worktree_path, null: false, unique: true
      String :phase, null: false, default: "spec_writing"
      String :saved_phase
      Integer :version, null: false, default: 0
      constraint(:workflow_phase, phase: %w[spec_writing spec_review spec_human_approval plan_writing plan_review plan_human_approval implementation implementation_review pr_ready done closed blocked paused cancelled])
      constraint(:workflow_version, Sequel.lit("version >= 0"))
      column :artifacts, :jsonb, null: false, default: Sequel.pg_jsonb({})
      String :blocker
      DateTime :archived_at
      DateTime :created_at, null: false, default: Sequel::SQL::Constants::CURRENT_TIMESTAMP
      index [:channel_id, :thread_id], unique: true, where: { archived_at: nil }
    end
    alter_table(:sessions) do
      add_foreign_key [:workflow_id], :workflows
    end
    create_table(:approvals) do
      String :id, primary_key: true
      foreign_key :workflow_id, :workflows, type: String, null: false
      String :kind, null: false
      constraint(:approval_kind, kind: %w[spec plan])
      String :target_commit, null: false
      String :user_id, null: false
      String :channel_id, null: false
      String :post_id, null: false
      DateTime :created_at, null: false, default: Sequel::SQL::Constants::CURRENT_TIMESTAMP
      unique [:workflow_id, :kind, :target_commit]
      unique :post_id
    end
  end
end

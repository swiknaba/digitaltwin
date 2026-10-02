# typed: strict
# frozen_string_literal: true

Sequel.migration do
  change do
    create_table(:reviews) do
      String :id, primary_key: true
      foreign_key :workflow_id, :workflows, type: String, null: false
      String :gate, null: false
      Integer :round, null: false
      String :target_commit, null: false
      String :base_commit
      String :review_commit
      String :review_path, null: false
      String :verdict
      column :reviewer_configuration, :jsonb, null: false
      DateTime :created_at, null: false, default: Sequel::SQL::Constants::CURRENT_TIMESTAMP
      unique [:workflow_id, :gate, :round]
      constraint(:review_verdict, Sequel.lit("verdict IS NULL OR verdict IN ('approve', 'changes_requested')"))
      constraint(:review_gate, gate: %w[spec plan implementation])
      constraint(:review_round, Sequel.lit("round >= 1"))
    end
    create_table(:queued_messages) do
      String :id, primary_key: true
      foreign_key :workflow_id, :workflows, type: String, null: false
      foreign_key :inbox_id, :inbox, type: String, null: false, unique: true
      Integer :workflow_version, null: false
      DateTime :created_at, null: false, default: Sequel::SQL::Constants::CURRENT_TIMESTAMP
    end
  end
end

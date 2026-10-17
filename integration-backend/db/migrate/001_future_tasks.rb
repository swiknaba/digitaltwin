# typed: strict
# frozen_string_literal: true

# Greenfield baseline: historical Mattermost/workflow schema lives in Git only.
Sequel.migration do
  change do
    create_table(:jobs) do
      String :id, primary_key: true
      String :dispatch_key, null: false, unique: true
      String :kind, null: false
      column :payload, :jsonb, null: false
      String :status, null: false, default: "pending"
      Integer :attempts, null: false, default: 0
      String :worker_id
      String :lease_token
      DateTime :lease_expires_at
      DateTime :available_at, null: false
      DateTime :effect_started_at
      String :last_error
      DateTime :created_at, null: false, default: Sequel::SQL::Constants::CURRENT_TIMESTAMP
      constraint(:job_status, status: %w[pending running complete blocked uncertain])
      constraint(:attempt_budget, Sequel.lit("attempts >= 0 AND attempts <= 5"))
      index [:status, :available_at]
    end

    create_table(:future_tasks) do
      String :id, primary_key: true
      String :actor_id, null: false
      String :origin, null: false, default: "commander"
      String :target, null: false, default: "commander"
      String :text, text: true, null: false
      column :references, :jsonb, null: false, default: Sequel.pg_jsonb([])
      String :timezone, null: false
      String :local_time, null: false
      DateTime :due_at, null: false
      Integer :version, null: false, default: 1
      String :state, null: false, default: "scheduled"
      String :idempotency_key, null: false
      String :idempotency_digest, null: false
      DateTime :created_at, null: false, default: Sequel::SQL::Constants::CURRENT_TIMESTAMP
      DateTime :updated_at, null: false, default: Sequel::SQL::Constants::CURRENT_TIMESTAMP
      unique [:actor_id, :idempotency_key]
      constraint(:future_task_target, target: ["commander"])
      constraint(:future_task_state, state: %w[scheduled running awaiting_disposition completed failed canceled uncertain])
      constraint(:future_task_version, Sequel.lit("version > 0"))
      index [:actor_id, :created_at, :id]
      index [:actor_id, :id]
      index [:state, :due_at]
    end

    create_table(:future_task_executions) do
      String :id, primary_key: true
      foreign_key :task_id, :future_tasks, type: String, null: false, on_delete: :cascade
      Integer :generation, null: false
      String :delivery_key, null: false, unique: true
      foreign_key :job_id, :jobs, type: String, null: false, on_delete: :restrict
      String :state, null: false, default: "queued"
      column :receipt, :jsonb
      DateTime :claimed_at
      DateTime :delivered_at
      DateTime :created_at, null: false, default: Sequel::SQL::Constants::CURRENT_TIMESTAMP
      DateTime :updated_at, null: false, default: Sequel::SQL::Constants::CURRENT_TIMESTAMP
      unique [:task_id, :generation]
      constraint(:future_task_execution_state, state: %w[queued claimed delivering delivered failed uncertain stale])
    end

    create_table(:future_task_delivery_attempts) do
      String :id, primary_key: true
      foreign_key :execution_id, :future_task_executions, type: String, null: false, on_delete: :cascade
      Integer :sequence, null: false
      String :state, null: false
      column :detail, :jsonb, null: false
      DateTime :created_at, null: false, default: Sequel::SQL::Constants::CURRENT_TIMESTAMP
      unique [:execution_id, :sequence]
      constraint(:future_task_delivery_attempt_state, state: %w[delivered uncertain failed canceled])
    end

    create_table(:future_task_dispositions) do
      String :id, primary_key: true
      foreign_key :task_id, :future_tasks, type: String, null: false, on_delete: :cascade
      foreign_key :execution_id, :future_task_executions, type: String, null: false, on_delete: :restrict
      String :idempotency_key, null: false
      String :outcome, null: false
      String :idempotency_digest, null: false
      DateTime :created_at, null: false, default: Sequel::SQL::Constants::CURRENT_TIMESTAMP
      unique [:task_id, :idempotency_key]
      constraint(:future_task_disposition_outcome, outcome: %w[assessed project_work_requested user_canceled rescheduled owner_failed owner_canceled])
    end

    create_table(:future_task_capability_uses) do
      String :id, primary_key: true
      String :capability_id, null: false, unique: true
      String :actor_id, null: false
      String :conversation_id, null: false
      DateTime :used_at, null: false
    end
  end
end

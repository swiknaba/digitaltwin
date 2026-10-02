# typed: strict
# frozen_string_literal: true

Sequel.migration do
  change do
    alter_table(:sessions) do
      add_column :runtime_identity, :jsonb
      add_column :workspace_id, String
    end
    alter_table(:workflows) do
      add_column :paused_commit, String
      add_foreign_key :source_inbox_id, :inbox
      add_column :role_configurations, :jsonb, null: false, default: Sequel.pg_jsonb({})
    end
    alter_table(:reviews) do
      add_column :dispatch_state, String, null: false, default: "queued"
      add_constraint(:review_dispatch_state, dispatch_state: %w[queued sending delivered uncertain])
    end
    create_table(:workflow_requests) do
      String :id, primary_key: true
      foreign_key :inbox_id, :inbox, null: false, unique: true
      foreign_key :project_id, :projects, type: String, null: false
      foreign_key :workflow_id, :workflows, type: String
      String :request_digest, null: false
      column :parameters, :jsonb, null: false
      String :state, null: false, default: "queued"
      String :thread_id
      String :reason
      DateTime :created_at, null: false, default: Sequel::SQL::Constants::CURRENT_TIMESTAMP
      constraint(:workflow_request_state, state: %w[queued sending uncertain bound blocked])
    end
    create_table(:session_operations) do
      String :id, primary_key: true
      foreign_key :session_id, :sessions, type: String, null: false
      String :kind, null: false
      String :state, null: false, default: "queued"
      String :reason
      constraint(:session_operation_kind, kind: %w[start stop])
      constraint(:session_operation_state, state: %w[queued sending uncertain complete blocked])
      unique [:session_id, :kind]
    end
    create_table(:master_requests) do
      String :id, primary_key: true
      foreign_key :inbox_id, :inbox, null: false, unique: true
      foreign_key :session_id, :sessions, type: String, null: false
      String :credential_digest, null: false, unique: true
      DateTime :expires_at, null: false
      String :state, null: false, default: "queued"
      String :reason
      constraint(:master_request_state, state: %w[queued active complete uncertain])
      index :session_id, unique: true, where: { state: "active" }
    end
  end
end

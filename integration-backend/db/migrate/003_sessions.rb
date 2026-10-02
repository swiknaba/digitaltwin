# typed: strict
# frozen_string_literal: true

# Storage contract only: session lifecycle remains gated on live CLI evidence.
Sequel.migration do
  change do
    create_table(:sessions) do
      String :id, primary_key: true
      String :workflow_id
      String :role, null: false
      Integer :generation, null: false
      String :pane_id, null: false
      String :alias, null: false
      column :configuration, :jsonb, null: false
      String :credential_digest, null: false, unique: true
      DateTime :credential_expires_at, null: false
      TrueClass :active, null: false, default: true
      DateTime :last_verified_at
      String :state, null: false, default: "unknown"
      unique [:workflow_id, :role, :generation]
      constraint(:session_role, role: %w[writer reviewer controller])
      constraint(:session_scope,
                 Sequel.lit("(role = 'controller' AND workflow_id IS NULL) OR (role <> 'controller' AND workflow_id IS NOT NULL)"))
    end
    create_table(:callbacks) do
      primary_key :id
      foreign_key :session_id, :sessions, type: String, null: false
      Integer :generation, null: false
      String :key, null: false
      String :body_digest, null: false
      unique [:session_id, :generation, :key]
    end
  end
end

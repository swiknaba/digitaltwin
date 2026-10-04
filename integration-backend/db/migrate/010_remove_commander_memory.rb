# typed: strict
# frozen_string_literal: true

# Migration 009 can already exist in an operator database. Remove its tables
# forward instead of rewriting history.
Sequel.migration do
  up do
    drop_table(:memory_operations)
    drop_table(:memory_entries)
  end

  down do
    create_table(:memory_entries) do
      String :id, primary_key: true
      String :scope, null: false
      foreign_key :project_id, :projects, type: String
      String :content, text: true, null: false
      String :source, null: false
      Integer :revision, null: false, default: 1
      DateTime :created_at, null: false, default: Sequel::SQL::Constants::CURRENT_TIMESTAMP
      DateTime :updated_at, null: false, default: Sequel::SQL::Constants::CURRENT_TIMESTAMP
      constraint(:memory_entry_scope, scope: %w[global project])
      constraint(:memory_entry_project_scope, Sequel.lit("(scope = 'global' AND project_id IS NULL) OR (scope = 'project' AND project_id IS NOT NULL)"))
    end
    create_table(:memory_operations) do
      String :id, primary_key: true
      foreign_key :entry_id, :memory_entries, type: String, null: false
      String :scope, null: false
      foreign_key :project_id, :projects, type: String
      String :idempotency_key, null: false
      String :kind, null: false
      DateTime :created_at, null: false, default: Sequel::SQL::Constants::CURRENT_TIMESTAMP
      constraint(:memory_operation_scope, scope: %w[global project])
      constraint(:memory_operation_kind, kind: %w[remember correct])
    end
    add_index :memory_operations, %i[scope idempotency_key], unique: true, where: { project_id: nil }
    add_index :memory_operations, %i[scope project_id idempotency_key], unique: true, where: Sequel.~(project_id: nil)
    add_index :memory_entries, %i[scope project_id created_at id]
  end
end

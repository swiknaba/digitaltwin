Sequel.migration do
  change do
    create_table(:conversation_bindings) do
      String :channel_id, null: false
      String :thread_id, null: false
      String :user_id, null: false
      foreign_key :workflow_id, :workflows, type: String, null: false
      foreign_key :inbox_id, :inbox, null: false
      DateTime :updated_at, null: false
      primary_key [:channel_id, :thread_id, :user_id]
    end
    create_table(:followups) do
      primary_key :id
      foreign_key :inbox_id, :inbox, null: false, unique: true
      foreign_key :workflow_id, :workflows, type: String, null: false
      foreign_key :session_id, :sessions, type: String
      Integer :generation
      String :status, null: false, default: "queued"
      String :reason
      column :evidence, :jsonb, null: false
      DateTime :created_at, null: false, default: Sequel::SQL::Constants::CURRENT_TIMESTAMP
      DateTime :delivered_at
      constraint(:followup_status, status: %w[queued sending delivered uncertain blocked])
    end
  end
end

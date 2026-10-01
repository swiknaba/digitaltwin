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
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      constraint(:job_status, status: %w[pending running complete blocked uncertain])
      constraint(:attempt_budget) { (attempts >= 0) & (attempts <= 5) }
      index [:status, :available_at]
    end
    create_table(:inbox) do
      primary_key :id
      String :channel_id, null: false
      String :post_id, null: false
      String :thread_id, null: false
      String :user_id, null: false
      String :event_kind, null: false
      Bignum :post_revision, null: false
      column :verified_delivery, :jsonb, null: false
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      unique [:channel_id, :post_id, :event_kind, :post_revision]
    end
    create_table(:chat_checkpoints) do
      String :channel_id, primary_key: true
      Bignum :post_revision, null: false, default: 0
    end
    create_table(:outbox) do
      String :id, primary_key: true
      String :response_key, null: false, unique: true
      String :channel_id, null: false
      String :thread_id
      String :bot, null: false
      String :role
      String :body, text: true, null: false
      String :status, null: false, default: "pending"
      String :remote_post_id
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      constraint(:outbox_status, status: %w[pending delivered uncertain blocked])
    end
    create_table(:audit) do
      primary_key :id
      String :event_key, null: false, unique: true
      String :action, null: false
      String :user_id
      String :channel_id
      String :post_id
      column :details, :jsonb, null: false
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
    end
  end
end

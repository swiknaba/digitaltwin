Sequel.migration do
  change do
    create_table(:projects) do
      String :id, primary_key: true
      String :channel_id, null: false, unique: true
      String :slug, null: false, unique: true
      String :remote_identity, null: false, unique: true
      String :workspace, null: false, unique: true
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
    end
  end
end

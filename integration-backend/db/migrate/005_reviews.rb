Sequel.migration do
  change do
    create_table(:reviews) do
      primary_key :id
      foreign_key :workflow_id, :workflows, type: String, null: false
      String :gate, null: false
      Integer :round, null: false
      String :target_commit, null: false
      String :base_commit
      String :review_commit
      String :review_path, null: false
      String :verdict
      column :reviewer_configuration, :jsonb, null: false
      unique [:workflow_id, :gate, :round]
      constraint(:review_verdict) { (verdict =~ nil) | (verdict =~ %w[approve changes_requested]) }
      constraint(:review_gate, gate: %w[spec plan implementation])
      constraint(:review_round) { round >= 1 }
    end
    create_table(:queued_messages) do
      primary_key :id
      foreign_key :workflow_id, :workflows, type: String, null: false
      foreign_key :inbox_id, :inbox, null: false, unique: true
      Integer :workflow_version, null: false
    end
  end
end

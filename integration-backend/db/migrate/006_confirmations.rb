# typed: strict
# frozen_string_literal: true

Sequel.migration do
  change do
    create_table(:confirmations) do
      String :id, primary_key: true
      String :requesting_user_id, null: false
      String :channel_id, null: false
      String :action, null: false
      String :parameter_digest, null: false
      DateTime :expires_at, null: false
      DateTime :consumed_at
      String :confirming_user_id
      String :confirming_post_id, unique: true
    end
  end
end

require_relative "../spec_helper"
RSpec.describe "Prepared schema constraints" do
  let(:db) { Kirei::App.raw_db_connection }
  it "rejects impossible workflow/session/review states" do
    db.transaction(rollback: :always) do
      db[:projects].insert(id: "constraint-project", channel_id: "constraint-channel", slug: "owner/constraints", remote_identity: "github.com/owner/constraints", workspace: "/tmp/constraints")
      args = { id: "constraint-workflow", project_id: "constraint-project", channel_id: "constraint-channel", thread_id: "thread", branch: "digitaltwin/constraints", worktree_path: "/tmp/constraint-worktree" }
      expect { db.transaction(savepoint: true) { db[:workflows].insert(**args, phase: "skip_every_gate") } }.to raise_error(Sequel::CheckConstraintViolation)
      db[:workflows].insert(**args)
      expect { db.transaction(savepoint: true) { db[:reviews].insert(workflow_id: args[:id], gate: "spec", round: 1, target_commit: "a", review_path: "review.md", reviewer_configuration: Sequel.pg_jsonb({}), verdict: "invented") } }.to raise_error(Sequel::CheckConstraintViolation)
    end
  end
end

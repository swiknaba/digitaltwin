require_relative "../spec_helper"
RSpec.describe "Session-bound Worker callbacks" do
  let(:db) { Kirei::App.raw_db_connection }
  before do
    %i[callbacks sessions approvals reviews queued_messages workflows projects outbox jobs].each { |t| db[t].delete }
    db[:projects].insert(id: "p", channel_id: "c", slug: "owner/repo", remote_identity: "github.com/owner/repo",
                         workspace: "/workspace/repos/owner/repo")
    db[:workflows].insert(id: "w", project_id: "p", channel_id: "c", thread_id: "root", branch: "digitaltwin/fixture",
                          worktree_path: "/workspace/worktrees/fixture")
    db[:sessions].insert(id: "s", workflow_id: "w", role: "writer", generation: 1, pane_id: "pane", alias: "alias",
                         configuration: Sequel.pg_jsonb({}), credential_digest: Digest::SHA256.hexdigest("fixture-token"), credential_expires_at: Time.now + 60)
    @service = Domains::Mattermost::WorkerChat.new
  end
  it "derives thread/bot/role and deduplicates retries" do
    2.times {
      expect(@service.post(token: "fixture-token", generation: 1, body: "question",
                           key: "message").status).to eq("accepted")
    }
    expect(db[:outbox].count).to eq(1)
    expect(db[:outbox].first.values_at(:channel_id, :thread_id, :bot, :role,
                                       :body)).to eq(["c", "root", "worker", "writer", "[writer] question"])
    expect(@service.post(token: "fixture-token", generation: 1, body: "changed",
                         key: "message").status).to eq("rejected")
  end
  it "rejects wrong credentials, stale generation, expired and inactive sessions" do
    expect(@service.post(token: "wrong", generation: 1, body: "q", key: "a").status).to eq("rejected")
    expect(@service.post(token: "fixture-token", generation: 2, body: "q", key: "a").status).to eq("rejected")
    db[:sessions].update(credential_expires_at: Time.now - 1)
    expect(@service.post(token: "fixture-token", generation: 1, body: "q", key: "a").status).to eq("rejected")
    db[:sessions].update(credential_expires_at: Time.now + 60, active: false)
    expect(@service.post(token: "fixture-token", generation: 1, body: "q", key: "a").status).to eq("rejected")
    expect(db[:outbox].count).to eq(0)
  end
  it "rejects closed workflow callbacks" do
    db[:workflows].update(phase: "closed", archived_at: Time.now)
    expect(@service.post(token: "fixture-token", generation: 1, body: "q", key: "a").status).to eq("rejected")
  end
  it "rejects a role outside its active workflow phase" do
    db[:sessions].update(role: "reviewer")
    expect(@service.post(token: "fixture-token", generation: 1, body: "q", key: "a").status).to eq("rejected")
  end
end

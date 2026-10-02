require_relative "../../spec_helper"
RSpec.describe Services::Sessions::PostWorkerChat do
  let(:db) { Kirei::App.raw_db_connection }
  before do
    %i[callbacks sessions approvals reviews queued_messages workflows projects outbox jobs].each { |t| db[t].delete }
    db[:projects].insert(id: "p", channel_id: "c", slug: "owner/repo", remote_identity: "github.com/owner/repo",
                         workspace: "/workspace/repos/owner/repo")
    db[:workflows].insert(id: "w", project_id: "p", channel_id: "c", thread_id: "root", branch: "digitaltwin/fixture",
                          worktree_path: "/workspace/worktrees/fixture", role_configurations: workflow_roles)
    db[:sessions].insert(id: "s", workflow_id: "w", role: "writer", generation: 1, pane_id: "pane", alias: "alias",
                         configuration: Sequel.pg_jsonb({}), credential_digest: Digest::SHA256.hexdigest("fixture-token"), credential_expires_at: Time.now + 60)
    @service = described_class.new
  end
  def post(**args) = @service.call(**args)
  def status(result) = result.success? ? "accepted" : "rejected"

  it "derives thread/bot/role and deduplicates retries" do
    2.times {
      expect(status(post(token: "fixture-token", generation: 1, body: "question",
                         key: "message"))).to eq("accepted")
    }
    expect(db[:outbox].count).to eq(1)
    expect(db[:outbox].first.values_at(:channel_id, :thread_id, :bot, :role,
                                       :body)).to eq(["c", "root", "worker", "writer", "[writer] question"])
    rejected = post(token: "fixture-token", generation: 1, body: "changed", key: "message")
    expect(rejected.errors.first&.detail).to eq("Callback key reused with changed body")
  end
  it "rejects wrong credentials, stale generation, expired and inactive sessions" do
    expect(status(post(token: "wrong", generation: 1, body: "q", key: "a"))).to eq("rejected")
    expect(status(post(token: "fixture-token", generation: 2, body: "q", key: "a"))).to eq("rejected")
    db[:sessions].update(credential_expires_at: Time.now - 1)
    expect(status(post(token: "fixture-token", generation: 1, body: "q", key: "a"))).to eq("rejected")
    db[:sessions].update(credential_expires_at: Time.now + 60, active: false)
    expect(status(post(token: "fixture-token", generation: 1, body: "q", key: "a"))).to eq("rejected")
    expect(db[:outbox].count).to eq(0)
  end
  it "rejects closed workflow callbacks" do
    db[:workflows].update(phase: "closed", archived_at: Time.now)
    expect(status(post(token: "fixture-token", generation: 1, body: "q", key: "a"))).to eq("rejected")
  end
  it "rejects a role outside its active workflow phase" do
    db[:sessions].update(role: "reviewer")
    expect(post(token: "fixture-token", generation: 1, body: "q", key: "a").errors.first&.detail).to eq("Session role is not active in this phase")
  end
  it "rolls back the fresh callback receipt when the outbox key already holds other content" do
    db[:outbox].insert(id: "existing", response_key: "callback:s:1:message", channel_id: "c", thread_id: "root", bot: "worker", role: "writer",
                       body: "[writer] other", status: "pending")
    result = post(token: "fixture-token", generation: 1, body: "question", key: "message")
    expect(result.errors.first&.detail).to eq("Response key reused with changed content")
    expect(db[:callbacks].count).to eq(0)
    expect(db[:outbox].select_map(:body)).to eq(["[writer] other"])
  end
end

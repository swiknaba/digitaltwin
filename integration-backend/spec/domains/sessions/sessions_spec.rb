require_relative "../../spec_helper"
RSpec.describe "Sessions domain" do
  let(:db) { Kirei::App.raw_db_connection }
  let(:dto) { Domains::Sessions::Dto }
  let(:registry) { Domains::Sessions::Registry.new }
  let(:operations) { Domains::Sessions::Operations.new }
  let(:writer) { Domains::Workflows::Dto::RoleConfig.from_hash(WorkflowFixtures::WORKFLOW_ROLES.fetch("writer")) }
  let(:identity) { { "source" => "fixture", "agent" => "codex", "kind" => "id", "value" => "conversation" } }

  before do
    db[:projects].insert(id: "project", channel_id: "c", slug: "owner/repo", remote_identity: "github.com/owner/repo", workspace: "/tmp/repo")
    db[:workflows].insert(id: "workflow", project_id: "project", channel_id: "c", thread_id: "root", branch: "b", worktree_path: "/tmp/w", role_configurations: workflow_roles)
  end

  def session(id, generation: 1, role: "writer", workflow_id: "workflow", **columns)
    db[:sessions].insert({ id: id, workflow_id: workflow_id, role: role, generation: generation, pane_id: id, alias: id, configuration: session_configuration(role),
                           credential_digest: Digest::SHA256.hexdigest("#{id}-token"), credential_expires_at: Time.now + 3600 }.merge(columns))
  end

  def reserve(id)
    operations.reserve(session_id: id, workflow_id: "workflow", role: dto::SessionRole::Writer, configuration: writer, credential_digest: "digest-#{id}")
  end

  describe "Authenticate" do
    let(:authenticate) { Domains::Sessions::Authenticate.new }

    it "authenticate rejects stale generation" do
      session("old")
      session("new", generation: 2)
      stale = authenticate.call(token: "old-token", generation: 1, roles: [dto::SessionRole::Writer])
      expect([stale.errors.first.code, stale.errors.first.detail]).to eq([dto::ErrorCode::StaleGeneration.serialize, "Invalid session"])
      expect(authenticate.call(token: "new-token", generation: 2, roles: [dto::SessionRole::Writer]).result.id).to eq("new")
    end

    it "rejects a wrong role, token, inactive or expired session" do
      session("writer")
      expect(authenticate.call(token: "writer-token", generation: 1, roles: [dto::SessionRole::Reviewer]).errors.first.code).to eq("invalid_session")
      expect(authenticate.call(token: "wrong", generation: 1, roles: [dto::SessionRole::Writer]).errors.first.code).to eq("invalid_session")
      db[:sessions].update(credential_expires_at: Time.now - 1)
      expect(authenticate.call(token: "writer-token", generation: 1, roles: [dto::SessionRole::Writer]).errors.first.code).to eq("invalid_session")
      db[:sessions].update(credential_expires_at: Time.now + 60, active: false)
      expect(authenticate.call(token: "writer-token", generation: 1, roles: [dto::SessionRole::Writer]).errors.first.code).to eq("invalid_session")
    end
  end

  describe "Operations" do
    it "reserve is idempotent while a start is pending" do
      first = reserve("session_first").result
      expect(first.kind).to eq(dto::OperationKind::Start)
      expect(reserve("session_second").result).to eq(first)
      expect(db[:sessions].select_map(:id)).to eq(["session_first"])
      expect(db[:jobs].where(dispatch_key: "session:start:session_first").count).to eq(1)
      operations.mark(id: first.id, state: dto::OperationState::Uncertain, reason: "Runtime effect requires reconciliation; do not repeat")
      expect(reserve("session_third").result).to eq(operations.find(id: first.id))
      row = db[:sessions].first
      expect(row.values_at(:generation, :pane_id, :alias, :active)).to eq([1, "pending:session_first", "digitaltwin-session_first", false])
      expect(row[:configuration].to_hash).to eq(writer.serialize)
    end

    it "reserves the next generation after a completed start, and fails while a session is active" do
      session("old", active: false)
      expect(reserve("session_next").result.session_id).to eq("session_next")
      expect(db[:sessions][id: "session_next"][:generation]).to eq(2)
      db[:session_operations].update(state: "complete")
      db[:sessions].where(id: "session_next").update(active: true)
      expect(reserve("session_other").errors.first.code).to eq(dto::ErrorCode::SessionActive.serialize)
    end

    it "rejects an incomplete configuration before writing" do
      blank = Domains::Workflows::Dto::RoleConfig.new(cli: "codex", provider: "", model: "m", family: "f", launch_args: [])
      result = operations.reserve(session_id: "s", workflow_id: "workflow", role: dto::SessionRole::Writer, configuration: blank, credential_digest: "d")
      expect(result.errors.first.detail).to eq("Incomplete role configuration")
      expect(db[:sessions].count).to eq(0)
    end

    it "queues one stop per active session" do
      session("writer")
      session("reviewer", role: "reviewer")
      2.times { operations.queue_stops(workflow_id: "workflow") }
      expect(db[:session_operations].where(kind: "stop").select_order_map(:session_id)).to eq(%w[reviewer writer])
      expect(db[:jobs].where(kind: "session.stop").count).to eq(2)
    end
  end

  describe "stored JSONB" do
    it "runtime_identity round-trips and rejects missing fields" do
      session("writer")
      operations.activate(session_id: "writer", identity: dto::RuntimeIdentity.from_hash(identity), state: dto::SessionState::Idle)
      expect(db[:sessions][id: "writer"][:runtime_identity].to_hash).to eq(identity)
      view = registry.find(id: "writer")
      expect([view.runtime_identity&.serialize, view.state, view.active]).to eq([identity, dto::SessionState::Idle, true])
      [identity.except("value"), identity.merge("extra" => "x"), identity.merge("kind" => 1)].each do |malformed|
        db[:sessions].where(id: "writer").update(runtime_identity: Sequel.pg_jsonb(malformed))
        expect { registry.find(id: "writer") }.to raise_error(Domains::Sessions::Errors::MalformedRecord)
      end
    end

    it "configuration round-trips and fails closed" do
      session("writer")
      expect(registry.find(id: "writer").configuration).to eq(writer)
      [{}, writer.serialize.except("model"), writer.serialize.merge("unknown" => "x"), writer.serialize.merge("launch_args" => [1])].each do |malformed|
        db[:sessions].where(id: "writer").update(configuration: Sequel.pg_jsonb(malformed))
        expect { registry.find(id: "writer") }.to raise_error(Domains::Sessions::Errors::MalformedRecord)
      end
      db[:sessions].where(id: "writer").update(configuration: Sequel.pg_jsonb(writer.serialize), state: "sleeping")
      expect { registry.find(id: "writer") }.to raise_error(Domains::Sessions::Errors::MalformedRecord)
    end
  end

  describe "Callbacks" do
    let(:callbacks) { Domains::Sessions::Callbacks.new }

    it "callback key reuse with changed body fails KeyReused" do
      session("writer")
      first = callbacks.record(session_id: "writer", generation: 1, key: "message", body_digest: "a").result
      expect(first).to match(/\Acallback_[A-Za-z0-9]{12}\z/)
      expect(callbacks.record(session_id: "writer", generation: 1, key: "message", body_digest: "a").result).to eq(first)
      reused = callbacks.record(session_id: "writer", generation: 1, key: "message", body_digest: "b")
      expect([reused.errors.first.code, reused.errors.first.detail]).to eq([dto::ErrorCode::KeyReused.serialize, "Callback key reused with changed body"])
      expect(db[:callbacks].count).to eq(1)
    end
  end

  describe "Registry and Renewals" do
    it "selects pending starts and the latest generation per scope" do
      session("old")
      session("starting", generation: 2, active: false)
      db[:session_operations].insert(id: "op", session_id: "starting", kind: "start")
      expect(registry.pending_start(workflow_id: "workflow", role: dto::SessionRole::Writer)&.id).to eq("starting")
      expect(registry.latest_generation(workflow_id: "workflow", role: dto::SessionRole::Writer)).to eq(2)
      expect(registry.latest_generation(workflow_id: "workflow", role: dto::SessionRole::Reviewer)).to eq(0)
      expect(registry.active(workflow_id: "workflow", role: dto::SessionRole::Writer).map(&:id)).to eq(["old"])
      expect(registry.active_controller).to be_nil
    end

    it "schedules a renewal five minutes before expiry, once per expiry" do
      expires = Time.now + 3600
      session("writer", credential_expires_at: expires)
      renewals = Domains::Sessions::Renewals.new
      view = T.must(registry.find(id: "writer"))
      2.times { renewals.schedule(session: view) }
      job = db[:jobs].where(kind: "session.renew").all
      expect(job.map { |row| row[:dispatch_key] }).to eq(["session:renew:writer:#{view.credential_expires_at.to_i}"])
      expect(job.first[:available_at]).to be_within(2).of(expires - 300)
    end
  end
end

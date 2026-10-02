require_relative "../../spec_helper"
RSpec.describe "Workflows domain" do
  let(:db) { Kirei::App.raw_db_connection }
  let(:dto) { Domains::Workflows::Dto }
  let(:catalog) { Domains::Workflows::Catalog.new }
  let(:transitions) { Domains::Workflows::Transitions.new }
  let(:channel) { "c" * 26 }
  let(:commit) { "a" * 40 }
  let(:roles) {
    { "writer" => { "cli" => "codex", "provider" => "openai", "model" => "fixture-gpt", "family" => "gpt", "launch_args" => ["--model", "fixture-gpt"] },
      "reviewer" => { "cli" => "claude", "provider" => "anthropic", "model" => "fixture-claude", "family" => "claude", "launch_args" => ["--model", "fixture-claude"] } }
  }
  let(:controller) { { "cli" => "gemini", "provider" => "google", "model" => "fixture-gemini", "family" => "gemini", "launch_args" => [] } }

  before do
    db[:projects].insert(id: "project", channel_id: channel, slug: "owner/repo", remote_identity: "github.com/owner/repo", workspace: "/tmp/repo")
  end

  def workflow(**columns)
    db[:workflows].insert({ id: "workflow", project_id: "project", channel_id: channel, thread_id: "t" * 26, branch: "digitaltwin/workflow",
                            worktree_path: "/tmp/workflow", role_configurations: workflow_roles }.merge(columns))
  end

  def control(action, expected_version, paused_commit: nil)
    transitions.control(workflow_id: "workflow", action: dto::ControlAction.deserialize(action), expected_version: expected_version, paused_commit: paused_commit)
  end

  def inbox(post_id, thread_id: "r" * 26)
    delivery = Domains::Messaging::Dto::VerifiedDelivery.new(
      channel_id: channel, thread_id: thread_id, post_id: post_id, post_revision: 1, event_kind: Domains::Messaging::Dto::EventKind::Posted, root_post: true,
      body: "Build this project", actor: Domains::Messaging::Dto::VerifiedActor.new(user_id: "u" * 26, channel_id: channel, member: true, bot: false)
    )
    id = db[:inbox].insert(id: "inbox_#{SecureRandom.hex(6)}", channel_id: channel, thread_id: thread_id, post_id: post_id, post_revision: 1, event_kind: "posted", user_id: delivery.actor.user_id,
                           verified_delivery: Sequel.pg_jsonb(delivery.serialize))
    [id, delivery]
  end

  describe "transitions" do
    it "control with stale expected_version fails VersionChanged and writes nothing" do
      workflow(version: 3)
      before = db[:workflows].first
      result = control("pause", 2, paused_commit: commit)
      expect(result.errors.first.code).to eq(dto::ErrorCode::VersionChanged.serialize)
      expect(result.errors.first.detail).to eq("Workflow version changed")
      expect(db[:workflows].first).to eq(before)
    end

    it "control on an archived workflow fails Inactive and writes nothing" do
      workflow(archived_at: Time.now)
      before = db[:workflows].first
      expect(control("cancel", 0).errors.first.code).to eq(dto::ErrorCode::Inactive.serialize)
      expect(db[:workflows].first).to eq(before)
    end

    it "resume restores saved_phase and clears paused_commit" do
      workflow(phase: "plan_review")
      paused = control("pause", 0, paused_commit: commit).result
      expect([paused.phase, paused.saved_phase, paused.paused_commit, paused.version]).to eq([dto::Phase::Paused, dto::Phase::PlanReview, commit, 1])
      resumed = control("resume", 1).result
      expect([resumed.phase, resumed.saved_phase, resumed.paused_commit, resumed.version]).to eq([dto::Phase::PlanReview, nil, nil, 2])
      expect(db[:workflows].first.values_at(:phase, :saved_phase, :paused_commit, :version)).to eq(["plan_review", nil, nil, 2])
    end

    it "rejects each control outside its phases without writing" do
      { "pause" => ["closed", dto::ErrorCode::CannotPause], "resume" => ["spec_writing", dto::ErrorCode::NotPaused],
        "finish" => ["pr_ready", dto::ErrorCode::NotDelivered], "cancel" => ["cancelled", dto::ErrorCode::AlreadyClosed] }.each do |action, (phase, code)|
        db[:workflows].delete
        workflow(phase: phase)
        before = db[:workflows].first
        expect(control(action, 0).errors.first.code).to eq(code.serialize)
        expect(db[:workflows].first).to eq(before)
      end
    end

    it "records an artifact and enters review, or saves the review phase while paused" do
      workflow(phase: "paused", saved_phase: "spec_writing", version: 4)
      ref = dto::ArtifactRef.new(commit: commit, path: "docs/spec.md")
      expect(transitions.record_artifact(workflow_id: "workflow", gate: dto::Gate::Spec, ref: ref, expected_version: 3).errors.first.code).to eq(dto::ErrorCode::VersionChanged.serialize)
      view = transitions.record_artifact(workflow_id: "workflow", gate: dto::Gate::Spec, ref: ref, expected_version: 4).result
      expect([view.phase, view.saved_phase, view.paused_commit, view.version, view.artifacts.spec]).to eq([dto::Phase::Paused, dto::Phase::SpecReview, commit, 5, ref])
    end

    it "advances only from the gate's human approval phase" do
      workflow(phase: "spec_review")
      expect(transitions.advance_approval(workflow_id: "workflow", gate: dto::Gate::Spec, expected_version: 0).errors.first.code).to eq(dto::ErrorCode::PhaseMismatch.serialize)
      db[:workflows].update(phase: "plan_human_approval")
      expect(transitions.advance_approval(workflow_id: "workflow", gate: dto::Gate::Plan, expected_version: 0).result.phase).to eq(dto::Phase::Implementation)
    end
  end

  describe "JSONB values" do
    it "artifact_set round-trips today's JSONB shape" do
      stored = { "spec" => { "commit" => commit, "path" => "docs/spec.md" }, "implementation" => { "commit" => "b" * 40, "path" => nil } }
      workflow(phase: "plan_writing", artifacts: Sequel.pg_jsonb(stored))
      view = T.must(catalog.find(id: "workflow"))
      expect(view.artifacts.spec).to eq(dto::ArtifactRef.new(commit: commit, path: "docs/spec.md"))
      expect(view.artifacts.implementation).to eq(dto::ArtifactRef.new(commit: "b" * 40, path: nil))
      expect(view.artifacts.serialize).to eq(stored)
      # list_workflows renders this hash, so its key order matches the stored JSONB.
      expect(JSON.generate(view.artifacts.serialize)).to eq(JSON.generate(db[:workflows].first[:artifacts].to_hash))

      plan = dto::ArtifactRef.new(commit: "c" * 40, path: "docs/plan.md")
      transitions.record_artifact(workflow_id: "workflow", gate: dto::Gate::Plan, ref: plan, expected_version: 0)
      expect(db[:workflows].first[:artifacts].to_hash).to eq(stored.merge("plan" => { "commit" => "c" * 40, "path" => "docs/plan.md" }))
    end

    it "malformed role_configurations row fails closed" do
      malformed = [
        {},
        roles.merge("writer" => roles.fetch("writer").except("model")),
        roles.merge("writer" => roles.fetch("writer").merge("unknown" => "x")),
        roles.merge("writer" => roles.fetch("writer").merge("launch_args" => [1])),
        roles.merge("writer" => roles.fetch("writer").merge("cli" => 1)),
        roles.merge("observer" => controller)
      ]
      malformed.each do |value|
        db[:workflows].delete
        workflow(role_configurations: Sequel.pg_jsonb(value))
        expect { catalog.find(id: "workflow") }.to raise_error(Domains::Workflows::Errors::MalformedRecord)
      end
    end

    it "malformed artifacts row fails closed" do
      [{ "spec" => { "path" => "docs/spec.md" } }, { "spec" => { "commit" => commit, "path" => nil, "extra" => 1 } }, { "review" => { "commit" => commit, "path" => nil } }].each do |value|
        db[:workflows].delete
        workflow(artifacts: Sequel.pg_jsonb(value))
        expect { catalog.find(id: "workflow") }.to raise_error(Domains::Workflows::Errors::MalformedRecord)
      end
    end

    it "persists role_configurations as the full role file, including the controller entry" do
      file = roles.merge("controller" => controller)
      assignments = Domains::Workflows::Records.role_assignments_from_json(JSON.generate(file))
      expect(assignments.controller&.cli).to eq("gemini")
      id, = inbox("p" * 26)
      parameters = dto::RequestParameters.new(title: "Project work", existing_thread: nil, roles: assignments)
      request = Domains::Workflows::Requests.new.create(inbox_id: id, project_id: "project", digest: "d", parameters: parameters, thread_id: nil).result
      draft = dto::WorkflowDraft.new(project_id: "project", channel_id: channel, thread_id: "t" * 26, worktree_root: "/workspace/worktrees", source_inbox_id: id,
                                     role_configurations: assignments)
      bound = Domains::Workflows::Requests.new.bind(id: request.id, workflow: draft).result
      expect(bound.id).to match(/\Aworkflow_[A-Za-z0-9]{12}\z/)
      expect([bound.branch, bound.worktree_path]).to eq(["digitaltwin/#{bound.id}", "/workspace/worktrees/#{bound.id}"])
      expect(db[:workflows].first[:role_configurations].to_hash).to eq(file)
      expect(db[:workflow_requests].first[:parameters].to_hash).to eq("title" => "Project work", "existing_thread" => nil, "roles" => file)
      expect(Domains::Workflows::Requests.new.bind(id: request.id, workflow: draft).result.id).to eq(bound.id)
    end

    it "parses ROLE_CONFIG_FILE strictly" do
      expect { Domains::Workflows::Records.role_assignments_from_json("{") }.to raise_error(Domains::Workflows::Errors::MalformedRecord)
      expect { Domains::Workflows::Records.role_assignments_from_json(JSON.generate(roles.except("reviewer"))) }.to raise_error(Domains::Workflows::Errors::MalformedRecord)
      expect(Domains::Workflows::Records.role_assignments_from_json(JSON.generate(roles)).serialize).to eq(roles)
    end
  end

  describe "start request digest" do
    let(:assignments) { dto::RoleAssignments.from_hash(roles) }

    def start(post_id, roles: assignments, existing_thread: nil)
      id, delivery = inbox(post_id, thread_id: existing_thread || ("r" * 26))
      source = double(call: Kirei::Services::Result.new(result: delivery))
      result = Services::Workflows::RequestStart.new(source: source, roles: roles).call(inbox_id: id, project_id: "project", title: "Project work", existing_thread: existing_thread)
      db[:workflow_requests][id: result.result]
    end

    # Expected digests were computed with the pre-refactor Provision#request formula:
    # Digest::SHA256.hexdigest(JSON.generate([project_id, { "title", "existing_thread", "roles" }])).
    it "keeps today's byte-identical digest and parameters" do
      row = start("p" * 26)
      expect(row[:request_digest]).to eq("503e395f5389fbb211fddee7c159740370401841f1b692d46f9cdc6caf0950c8")
      expect(row[:parameters].to_hash).to eq("title" => "Project work", "existing_thread" => nil, "roles" => roles)
      expect(start("q" * 26, existing_thread: "t" * 26)[:request_digest]).to eq("b411fe0314b77bd94e3224a56fa1496cc33159acac4b9d8c5c82329ff2b39d3e")
      with_controller = dto::RoleAssignments.from_hash(roles.merge("controller" => controller))
      expect(start("s" * 26, roles: with_controller)[:request_digest]).to eq("c7d82467e97889d6285791aa77cc9d6134a6998ce0f914789961cc54e5f25e42")
    end

    it "fails without role configuration or for an unknown project" do
      id, delivery = inbox("p" * 26)
      source = double(call: Kirei::Services::Result.new(result: delivery))
      expect(Services::Workflows::RequestStart.new(source: source, roles: nil).call(inbox_id: id, project_id: "project", title: "Work").errors.first.detail).to eq("Role configuration missing")
      expect(Services::Workflows::RequestStart.new(source: source, roles: assignments).call(inbox_id: id, project_id: "missing", title: "Work").errors.first.detail).to eq("Unknown project")
      expect(db[:workflow_requests].count).to eq(0)
    end
  end

  describe "approvals" do
    let(:approvals) { Domains::Workflows::Approvals.new }

    it "binds one chat post to one exact approval and keeps the first approval of a commit" do
      workflow(phase: "spec_human_approval")
      args = { workflow_id: "workflow", gate: dto::Gate::Spec, target_commit: commit, user_id: "u", channel_id: channel, post_id: "post-1" }
      first = approvals.record(**args).result
      expect(approvals.record(**args).result).to eq(first)
      expect(approvals.record(**args.merge(target_commit: "b" * 40)).errors.first.code).to eq(dto::ErrorCode::ApprovalSourceBound.serialize)
      expect(approvals.record(**args.merge(post_id: "post-2")).result.id).to eq(first.id)
      expect(db[:approvals].count).to eq(1)
      expect(approvals.find(workflow_id: "workflow", gate: dto::Gate::Spec, commit: commit)).to eq(first)
    end
  end

  describe "queued messages" do
    it "returns held messages oldest first and removes released ones" do
      workflow(phase: "spec_review")
      first, = inbox("p" * 26)
      second, = inbox("q" * 26)
      queue = Domains::Workflows::QueuedMessages.new
      [first, second].each { |id| queue.enqueue(workflow_id: "workflow", inbox_id: id, workflow_version: 0) }
      held = queue.pending(workflow_id: "workflow")
      expect(held.map(&:inbox_id)).to eq([first, second])
      queue.remove(id: held.first.id)
      expect(queue.pending(workflow_id: "workflow").map(&:inbox_id)).to eq([second])
    end
  end
end

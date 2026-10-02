require_relative "../spec_helper"
RSpec.describe "Workflow/session/review lifecycle (isolated PostgreSQL fixtures)" do
  let(:db) { Kirei::App.raw_db_connection }
  let(:policy) { double(dispatch_allowed?: true) }
  let(:channel) { "c" * 26 }
  let(:master_channel) { "m" * 26 }
  let(:bot) { "b" * 26 }
  let(:commit) { "a" * 40 }
  let(:review_commit) { "b" * 40 }
  let(:roles) {
    { "writer" => { "cli" => "codex", "provider" => "openai", "model" => "fixture-gpt", "family" => "gpt", "launch_args" => ["--model", "fixture-gpt"] },
      "reviewer" => { "cli" => "claude", "provider" => "anthropic", "model" => "fixture-claude", "family" => "claude", "launch_args" => ["--model", "fixture-claude"] } }
  }
  let(:source) { double(call: Kirei::Services::Result.new(result: delivery)) }
  let(:delivery) {
    Domains::Messaging::Dto::VerifiedDelivery.new(channel_id: master_channel, thread_id: "r" * 26, post_id: "p" * 26, post_revision: 1,
                                                  event_kind: Domains::Messaging::Dto::EventKind::Posted, root_post: true, body: "Build this project", actor: Domains::Messaging::Dto::VerifiedActor.new(user_id: "u" * 26, channel_id: master_channel, member: true, bot: false))
  }
  let(:worktrees) { double }
  let(:routing) { double(route: { id: 123 }) }
  let(:evidence) { double(artifact: true, review: true, approval: true, approved_artifact: true, head: commit, current: commit, base: "f" * 40) }
  let(:herdr) { double }
  # Synthetic Mattermost transport at the Client boundary.
  let(:client) { double }
  let(:api) { Adapters::Mattermost::Api.new(client: client) }
  let(:credentials) { Adapters::Credentials::FileStore.new(root: @credential_root) }
  let(:renewals) { Domains::Sessions::Renewals.new }
  let(:reserve_session) { Services::Sessions::ReserveSession.new(source: source, credentials: credentials) }
  let(:bootstrap) { Services::Sessions::BootstrapController.new(credentials: credentials) }
  let(:execute_operation) { Services::Sessions::ExecuteOperation.new(herdr: herdr, source: source, credentials: credentials, callback_url: "http://fixture.invalid", policy: policy) }
  let(:renew_service) { Services::Sessions::Renew.new(herdr: herdr, source: source, credentials: credentials, policy: policy, renewals: renewals) }
  let(:reconcile_operation) { Services::Sessions::ReconcileOperation.new(db, herdr: herdr, source: source, credentials: credentials) }
  let(:stop_sessions) { Services::Sessions::StopWorkflowSessions.new }
  let(:role_assignments) { Domains::Workflows::Dto::RoleAssignments.from_hash(roles) }
  let(:request_start) { Services::Workflows::RequestStart.new(source: source, roles: role_assignments) }
  let(:provision) { Services::Workflows::Provision.new(db, source: source, api: api, bot_id: bot, worktrees: worktrees, reserve_session: reserve_session, policy: policy) }
  let(:reconcile_start) { Services::Workflows::ReconcileStart.new(source: source, api: api, bot_id: bot) }
  let(:reviews) { Domains::Reviews::Coordinator.new(db, herdr: herdr, evidence: evidence, routing: routing, policy: policy) }
  let(:control_service) { Services::Workflows::Control.new(source: source, herdr: herdr, evidence: evidence, reviews: reviews, stop_sessions: stop_sessions) }
  let(:advance) { Services::Workflows::AdvanceApproval.new(evidence: evidence, reviews: reviews, latest_review: Services::Workflows::LatestReview.new(db)) }
  let(:dispatch) { Services::Workflows::DispatchPhasePrompt.new(source: source, herdr: herdr, evidence: evidence, latest_review: Services::Workflows::LatestReview.new(db), policy: policy) }
  before do
    @credential_root = Dir.mktmpdir
    @inbox = db[:inbox].insert(id: "inbox_1", channel_id: master_channel, thread_id: delivery.thread_id, post_id: delivery.post_id, post_revision: 1,
                               event_kind: "posted", user_id: delivery.actor.user_id, verified_delivery: Sequel.pg_jsonb(delivery.serialize))
    db[:projects].insert(id: "project", channel_id: channel, slug: "owner/repo", remote_identity: "github.com/owner/repo", workspace: "/workspace/repos/owner/repo")
    allow(worktrees).to receive(:call) { |**args| Kirei::Services::Result.new(result: "/workspace/worktrees/#{args[:workflow_id]}") }
    allow(client).to receive(:get) do |path|
      path.end_with?("/users/me") ? { "id" => bot, "is_bot" => true } : { "channel_id" => channel, "user_id" => bot }
    end
    allow(client).to receive(:post) do |_path, payload|
      payload.merge("id" => "t" * 26, "user_id" => bot, "create_at" => 1, "update_at" => 1, "delete_at" => 0)
    end
    allow(herdr).to receive(:pane) do |pane|
      s = db[:sessions][pane_id: pane]
      herdr_pane("agent_session" => s[:runtime_identity]&.to_hash, "agent_status" => "idle", "pane_id" => pane, "name" => s[:alias], "cwd" => "/workspace/worktrees/workflow", "agent" => s[:configuration]["cli"], "interactive_ready" => true, "launch_pending" => false)
    end
    allow(herdr).to receive(:prompt)
    allow(herdr).to receive(:close)
  end
  after { FileUtils.remove_entry(@credential_root) }

  def workflow(phase: "spec_writing", active_sessions: true)
    db[:workflows].insert(id: "workflow", project_id: "project", channel_id: channel, thread_id: "t" * 26, branch: "digitaltwin/workflow", worktree_path: "/workspace/worktrees/workflow",
                          source_inbox_id: @inbox, role_configurations: Sequel.pg_jsonb(roles), phase: phase)
    return unless active_sessions

    %w[writer reviewer].each do |role|
      db[:sessions].insert(id: role, workflow_id: "workflow", role: role, generation: 1, pane_id: role, alias: role,
                           configuration: Sequel.pg_jsonb(roles[role]), credential_digest: Digest::SHA256.hexdigest("#{role}-token"), credential_expires_at: Time.now + 3600,
                           runtime_identity: Sequel.pg_jsonb({ "source" => "fixture", "agent" => roles[role]["cli"], "kind" => "id", "value" => "#{role}-conversation" }))
    end
  end

  def request(title)
    Platform::Unwrap.call(request_start.call(inbox_id: @inbox, project_id: "project", title: title))
  end

  # Runs one workflow.provision job for the request and returns its state.
  def provision_request(id, service = provision)
    kind = Platform::Jobs::Dto::JobKind::WorkflowProvision
    key = "spec:provision:#{SecureRandom.uuid}"
    Platform::Jobs::Store.new.enqueue(kind: kind, payload: Domains::Workflows::Dto::ProvisionJob.new(request_id: id), dispatch_key: key)
    # Leaves the request's own provision job unclaimed, as a direct call did.
    db[:jobs].exclude(dispatch_key: key).update(available_at: Time.now + 3600)
    service.call(job: T.must(Platform::Jobs::Store.new.claim(worker_id: "fixture")))
    db[:workflow_requests][id: id][:state]
  end

  # Runs one master.control job, the Master tool's path into Control.
  def control(action, expected_version)
    kind = Platform::Jobs::Dto::JobKind::MasterControl
    payload = Domains::Commander::Dto::MasterControlJob.new(inbox_id: @inbox, workflow_id: "workflow", action: action, expected_version: expected_version)
    Platform::Jobs::Store.new.enqueue(kind: kind, payload: payload, dispatch_key: "spec:control:#{SecureRandom.uuid}")
    control_service.call(job: claim_job(kind))
  end

  def reserve(role)
    Platform::Unwrap.call(reserve_session.call(workflow_id: "workflow", role: Domains::Sessions::Dto::SessionRole.deserialize(role)))
  end

  # Runs one claimed job of `kind` with `payload` through `service`. The job
  # under test is removed afterwards, so it does not count in assertions.
  def run_job(service, kind, payload)
    key = "spec:#{kind.serialize}:#{SecureRandom.uuid}"
    Platform::Jobs::Store.new.enqueue(kind: kind, payload: payload, dispatch_key: key)
    db[:jobs].exclude(dispatch_key: key).update(available_at: Time.now + 3600)
    service.call(job: T.must(Platform::Jobs::Store.new.claim(worker_id: "fixture")))
  ensure
    db[:jobs].where(dispatch_key: key).delete
  end

  # Runs the session operation as a session.start/stop job and returns its stored state.
  def execute(operation_id)
    kind = db[:session_operations][id: operation_id][:kind] == "start" ? Platform::Jobs::Dto::JobKind::SessionStart : Platform::Jobs::Dto::JobKind::SessionStop
    run_job(execute_operation, kind, Domains::Sessions::Dto::SessionOperationJob.new(operation_id: operation_id))
    db[:session_operations][id: operation_id][:state]
  end

  def renew(session_id:, generation:)
    run_job(renew_service, Platform::Jobs::Dto::JobKind::SessionRenew, Domains::Sessions::Dto::RenewalJob.new(session_id: session_id, generation: generation))
  end

  def reconcile(**args) = Platform::Unwrap.call(reconcile_operation.call(**args))

  def advance_approval(gate)
    Platform::Unwrap.call(advance.call(workflow_id: "workflow", gate: Domains::Workflows::Dto::Gate.deserialize(gate)))
  end

  def review_job(id)
    tick_job(Platform::Jobs::Dto::JobKind::ReviewPrompt) { |job| reviews.call(job: job) }
    expect(db[:reviews][id: id][:dispatch_state]).to eq("delivered")
  end

  it "creates one verified project thread and isolated workflow/worktree despite duplicate starts" do
    id = request("Project work")
    expect(request("Project work")).to eq(id)
    expect(provision_request(id)).to eq("bound")
    expect(provision_request(id)).to eq("bound")
    expect(client).to have_received(:post).once
    expect(db[:workflows].count).to eq(1)
    expect(db[:sessions].count).to eq(2)
    expect(db[:sessions].where(active: true).count).to eq(0)
    expect(db[:session_operations].count).to eq(2)
    expect(db[:conversation_bindings][inbox_id: @inbox][:workflow_id]).to eq(db[:workflows].first[:id])
    expect { request("Different work") }.to raise_error(ArgumentError)
  end
  it "retains uncertain thread creation and never resends" do
    allow(client).to receive(:post).and_raise(IOError)
    id = request("Project work")
    expect(provision_request(id)).to eq("uncertain")
    expect(provision_request(id)).to eq("uncertain")
    expect(client).to have_received(:post).once
    expect(db[:workflows].count).to eq(0)
  end
  it "raises the worktree failure and reserves no sessions" do
    id = request("Project work")
    rejected = Kirei::Services::Result.new(errors: Platform::Failure.call(code: Domains::Projects::Dto::ErrorCode::WorkspaceRejected, detail: "Workspace escape"))
    allow(worktrees).to receive(:call).and_return(rejected)
    expect { provision_request(id) }.to raise_error(ArgumentError, "Workspace escape")
    expect(db[:sessions].count).to eq(0)
    expect(db[:workflow_requests][id: id][:state]).to eq("queued")
  end
  it "raises for an unknown project without creating a thread" do
    id = request("Project work")
    missing = Services::Workflows::Provision.new(db, source: source, api: api, bot_id: bot, worktrees: worktrees, reserve_session: reserve_session, policy: policy, directory: double(find: nil))
    expect { provision_request(id, missing) }.to raise_error(ArgumentError, "Unknown project")
    expect(client).not_to have_received(:post)
    expect(db[:workflows].count).to eq(0)
  end
  it "keeps real dispatch gated despite durable starts" do
    id = request("Project work")
    gated = Services::Workflows::Provision.new(db, source: source, api: api, bot_id: bot, worktrees: worktrees, reserve_session: reserve_session)
    expect(provision_request(id, gated)).to eq("queued")
    expect(client).not_to have_received(:post)
  end
  it "starts the reserved session with callback environment and binds real conversation identity" do
    workflow(active_sessions: false)
    id = reserve("writer")
    expect(reserve("writer")).to eq(id)
    allow(herdr).to receive(:create_workspace).and_return(herdr_workspace(workspace_id: "runtime-workspace", pane_id: "pane"))
    identity = { "source" => "fixture", "agent" => "codex", "kind" => "id", "value" => "actual-conversation" }
    allow(herdr).to receive(:start).and_return(herdr_pane("agent_session" => identity, "agent_status" => "idle"))
    op = db[:session_operations][session_id: id]
    expect(execute(op[:id])).to eq("complete")
    expect(execute(op[:id])).to eq("complete")
    expect(db[:sessions][id: id][:runtime_identity]).to eq(identity)
    launch = Adapters::Herdr::Dto::LaunchSpec.new(cli: "codex", launch_args: ["--model", "fixture-gpt"])
    expect(herdr).to have_received(:start).once.with(pane_id: "pane", name: "digitaltwin-#{id}", launch: launch)
    expect(herdr).to have_received(:create_workspace).with(hash_including(env: hash_including("DIGITALTWIN_SESSION_GENERATION" => "1",
                                                                                              "DIGITALTWIN_SESSION_TOKEN_FILE" => File.join(@credential_root, "#{id}.token"))))
    expect(File.stat(File.join(@credential_root, "#{id}.token")).mode & 0777).to eq(0600)
    expect { reserve("controller") }.to raise_error(ArgumentError)
  end
  it "does not repeat an uncertain session start or create another conversation" do
    workflow(active_sessions: false)
    id = reserve("writer")
    allow(herdr).to receive(:create_workspace).and_raise(IOError)
    op = db[:session_operations][session_id: id]
    expect(execute(op[:id])).to eq("uncertain")
    expect(reserve("writer")).to eq(id)
    expect(execute(op[:id])).to eq("uncertain")
    expect(herdr).to have_received(:create_workspace).once
  end
  it "freezes review, dispatches one reviewer prompt, and releases changes to the same writer" do
    workflow
    id = reviews.ready(token: "writer-token", generation: 1, kind: "spec", commit: commit)
    expect(reviews.ready(token: "writer-token", generation: 1, kind: "spec", commit: commit)).to eq(id)
    expect(db[:workflows].first[:phase]).to eq("spec_review")
    review_job(id)
    db[:queued_messages].insert(id: "queued_message_1", workflow_id: "workflow", inbox_id: @inbox, workflow_version: 1)
    reviews.finish(token: "reviewer-token", generation: 1, review_commit: review_commit, verdict: "changes_requested")
    expect(db[:workflows].first[:phase]).to eq("spec_writing")
    expect(db[:jobs].where(kind: "review.release").count).to eq(1)
    reviews.release("workflow")
    expect(routing).to have_received(:route).with(inbox_id: @inbox)
    expect(db[:queued_messages].count).to eq(0)
    expect(db[:sessions].where(role: "writer").count).to eq(1)
  end
  it "requires exact approving review and human artifact approval before next phase" do
    workflow
    id = reviews.ready(token: "writer-token", generation: 1, kind: "spec", commit: commit)
    review_job(id)
    reviews.finish(token: "reviewer-token", generation: 1, review_commit: review_commit, verdict: "approve")
    expect(db[:workflows].first[:phase]).to eq("spec_human_approval")
    expect { advance_approval("spec") }.to raise_error(ArgumentError)
    db[:approvals].insert(id: "approval_1", workflow_id: "workflow", kind: "spec", target_commit: commit, user_id: delivery.actor.user_id, channel_id: master_channel, post_id: delivery.post_id)
    advance_approval("spec")
    expect(db[:workflows].first[:phase]).to eq("plan_writing")
    expect(db[:jobs].where(kind: "workflow.phase_prompt").count).to eq(1)
  end
  it "rejects unknown Writer state, wrong callback role/generation and nondiverse reviewer" do
    workflow
    allow(herdr).to receive(:pane).and_return(herdr_pane("agent_status" => "unknown"))
    expect { reviews.ready(token: "writer-token", generation: 1, kind: "spec", commit: commit) }.to raise_error(ArgumentError)
    expect { reviews.ready(token: "reviewer-token", generation: 1, kind: "spec", commit: commit) }.to raise_error(ArgumentError)
    expect { reviews.ready(token: "writer-token", generation: 2, kind: "spec", commit: commit) }.to raise_error(ArgumentError)
    expect(db[:reviews].count).to eq(0)
  end
  it "keeps pause orthogonal to callback completion and refuses unverified revision changes on resume" do
    workflow
    control("pause", 0)
    id = reviews.ready(token: "writer-token", generation: 1, kind: "spec", commit: commit)
    expect(db[:workflows].first.values_at(:phase, :saved_phase)).to eq(["paused", "spec_review"])
    allow(evidence).to receive(:current).and_return("f" * 40)
    expect { control("resume", 2) }.to raise_error(ArgumentError)
    allow(evidence).to receive(:current).and_return(commit)
    control("resume", 2)
    expect(db[:workflows].first[:phase]).to eq("spec_review")
    expect(db[:reviews][id: id][:target_commit]).to eq(commit)
  end
  it "finishes only delivered work and archives only after both session stops are confirmed" do
    workflow
    expect { control("finish", 0) }.to raise_error(ArgumentError)
    db[:workflows].update(phase: "done")
    control("finish", 0)
    expect(db[:workflows].first[:archived_at]).to be_nil
    db[:session_operations].where(kind: "stop").each { |op| expect(execute(op[:id])).to eq("complete") }
    expect(db[:workflows].first[:archived_at]).not_to be_nil
    expect(db[:sessions].where(active: true).count).to eq(0)
  end
  it "retains a durable release across callback replay and one invalid queued source" do
    workflow
    id = reviews.ready(token: "writer-token", generation: 1, kind: "spec", commit: commit)
    review_job(id)
    db[:queued_messages].insert(id: "queued_message_1", workflow_id: "workflow", inbox_id: @inbox, workflow_version: 1)
    allow(routing).to receive(:route).and_raise(ArgumentError, "Revoked source")
    reviews.finish(token: "reviewer-token", generation: 1, review_commit: review_commit, verdict: "changes_requested")
    reviews.finish(token: "reviewer-token", generation: 1, review_commit: review_commit, verdict: "changes_requested")
    expect(db[:jobs].where(kind: "review.release").count).to eq(1)
    reviews.release("workflow")
    expect(db[:queued_messages].count).to eq(1)
    expect(db[:audit].where(action: "release_source_rejected").count).to eq(1)
    allow(routing).to receive(:route).and_return({ id: 123 })
    reviews.release("workflow")
    expect(db[:queued_messages].count).to eq(0)
  end

  it "renews an expired same conversation without new sessions and rejects replacement" do
    workflow
    File.write(File.join(@credential_root, "writer.token"), "writer-token")
    db[:sessions].where(id: "writer").update(credential_expires_at: Time.now - 1)
    renew(session_id: "writer", generation: 1)
    expect(db[:sessions][id: "writer"][:credential_expires_at]).to be > Time.now
    expect(db[:sessions].count).to eq(2)
    expect(db[:jobs].where(kind: "session.renew").first[:available_at]).to be > Time.now + 3000
    allow(herdr).to receive(:pane).and_return(herdr_pane("agent_session" => { "value" => "replacement" }, "agent_status" => "idle"))
    expect { renew(session_id: "writer", generation: 1) }.to raise_error(ArgumentError)
  end

  it "authenticates callback intake without HTTP socket or Git effects and deduplicates" do
    workflow
    intake = Domains::Reviews::Intake.new
    2.times { expect(intake.enqueue(token: "writer-token", generation: 1, action: "artifact", kind: "spec", commit: commit)).to eq("queued") }
    expect(db[:jobs].where(kind: "review.callback").count).to eq(1)
    expect(db[:reviews].count).to eq(0)
    expect(herdr).not_to have_received(:pane)
    expect { intake.enqueue(token: "reviewer-token", generation: 1, action: "artifact", kind: "spec", commit: commit) }.to raise_error(ArgumentError)
  end
  it "rolls back terminal transition when durable session cleanup cannot be queued" do
    workflow(phase: "done")
    allow(stop_sessions).to receive(:call).and_raise(IOError, "Database enqueue failed")
    expect { control("finish", 0) }.to raise_error(IOError)
    expect(db[:workflows].first.values_at(:phase, :version)).to eq(["done", 0])
  end

  it "rolls back credential extension when its next renewal cannot be scheduled" do
    workflow
    File.write(File.join(@credential_root, "writer.token"), "writer-token")
    expiry = Time.now - 1
    db[:sessions].where(id: "writer").update(credential_expires_at: expiry)
    allow(renewals).to receive(:schedule).and_raise(IOError)
    expect { renew(session_id: "writer", generation: 1) }.to raise_error(IOError)
    expect(db[:sessions][id: "writer"][:credential_expires_at]).to be < Time.now
  end

  it "releases later messages despite a deleted Mattermost source" do
    workflow
    second = db[:inbox].insert(id: "inbox_2", channel_id: master_channel, thread_id: "second", post_id: "second-post", post_revision: 1, event_kind: "posted", user_id: delivery.actor.user_id, verified_delivery: Sequel.pg_jsonb(delivery.serialize))
    [@inbox, second].each { |id| db[:queued_messages].insert(id: "queued_message_#{id}", workflow_id: "workflow", inbox_id: id, workflow_version: 0) }
    allow(routing).to receive(:route).with(inbox_id: @inbox).and_raise(Adapters::Mattermost::Errors::RequestFailed.new("Mattermost HTTP 404", status: 404))
    reviews.release("workflow")
    expect(db[:queued_messages].select_map(:inbox_id)).to eq([@inbox])
    expect(routing).to have_received(:route).with(inbox_id: second)
  end

  it "keeps Master busy requests pending and recovers expired requests only for the bound human" do
    config = Domains::Workflows::Dto::RoleConfig.from_hash(roles["writer"].merge("cli" => "gemini", "provider" => "google", "family" => "gemini"))
    sid = Platform::Unwrap.call(bootstrap.call(configuration: config))
    identity = { "source" => "fixture", "agent" => "gemini", "kind" => "id", "value" => "master-conversation" }
    db[:sessions].where(id: sid).update(active: true, pane_id: "master-pane", runtime_identity: Sequel.pg_jsonb(identity))
    master = Domains::Commander::Master.new(db, bootstrap: bootstrap, source: source, herdr: herdr, configuration: config, credential_root: @credential_root, policy: policy)
    request = master.ingest(@inbox)
    dispatch = Platform::Jobs::Dto::JobKind::MasterDispatch
    allow(herdr).to receive(:pane).and_return(herdr_pane("agent_session" => identity, "agent_status" => "working"))
    tick_job(dispatch) { |job| master.call(job: job) }
    job = db[:jobs][kind: dispatch.serialize]
    expect(job.values_at(:status, :attempts)).to eq(["pending", 0])
    db[:jobs].where(id: job[:id]).update(available_at: Time.now - 1)
    allow(herdr).to receive(:pane).and_return(herdr_pane("agent_session" => identity, "agent_status" => "idle"))
    tick_job(dispatch) { |claimed| master.call(job: claimed) }
    expect(db[:jobs][id: job[:id]][:status]).to eq("complete")
    expect(db[:master_requests][id: request][:state]).to eq("active")
    token = File.read(File.join(@credential_root, "#{request}.request-token"))
    2.times { master.reply(request_id: request, token: token, text: "Instruction queued") }
    expect(db[:outbox].where(response_key: "master:reply:#{request}").count).to eq(1)
    expect { master.reply(request_id: request, token: token, text: "Changed") }.to raise_error(ArgumentError)
    db[:master_requests].where(id: request).update(state: "uncertain", expires_at: Time.now - 1)
    recovery = delivery.dup
    allow(recovery).to receive(:body).and_return("@agent recover-master #{request}")
    allow(source).to receive(:call).and_return(Kirei::Services::Result.new(result: recovery))
    master.recover(request_id: request, inbox_id: @inbox)
    expect(db[:master_requests][id: request][:state]).to eq("complete")
  end
  it "preserves queue order across transient source revalidation failures" do
    workflow
    second = db[:inbox].insert(id: "inbox_2", channel_id: master_channel, thread_id: "second", post_id: "second-post", post_revision: 1, event_kind: "posted", user_id: delivery.actor.user_id, verified_delivery: Sequel.pg_jsonb(delivery.serialize))
    [@inbox, second].each { |id| db[:queued_messages].insert(id: "queued_message_#{id}", workflow_id: "workflow", inbox_id: id, workflow_version: 0) }
    allow(routing).to receive(:route).with(inbox_id: @inbox).and_raise(Adapters::Mattermost::Errors::RequestFailed.new("Mattermost HTTP 500", status: 500))
    expect { reviews.release("workflow") }.to raise_error(Adapters::Mattermost::Errors::RequestFailed)
    expect(routing).not_to have_received(:route).with(inbox_id: second)
    expect(db[:queued_messages].count).to eq(2)
  end
  it "reconciles a lost thread receipt by exact bot root evidence without posting again" do
    allow(client).to receive(:post).and_raise(IOError)
    id = request("Project work")
    expect(provision_request(id)).to eq("uncertain")
    thread_id = "t" * 26
    root = { "id" => thread_id, "channel_id" => channel, "root_id" => "", "create_at" => 1, "update_at" => 1, "delete_at" => 0, "user_id" => bot, "message" => "Project work",
             "props" => { "digitaltwin_workflow_request" => id } }
    allow(client).to receive(:get).with("/api/v4/posts/#{thread_id}").and_return(root)
    recovery = delivery.dup
    allow(recovery).to receive(:body).and_return("@agent recover-start #{id} #{thread_id}")
    allow(source).to receive(:call).and_return(Kirei::Services::Result.new(result: recovery))
    2.times { expect(Platform::Unwrap.call(reconcile_start.call(request_id: id, inbox_id: @inbox, thread_id: thread_id)).serialize).to eq("queued") }
    expect(provision_request(id)).to eq("bound")
    expect(client).to have_received(:post).once
    expect(db[:workflows].count).to eq(1)
    expect(db[:audit].where(action: "verified_thread_reconciliation").count).to eq(1)
  end

  it "reconciles a started role against its exact alias cwd CLI and conversation without restarting" do
    workflow(active_sessions: false)
    sid = reserve("writer")
    allow(herdr).to receive(:create_workspace).and_return(herdr_workspace(workspace_id: "runtime", pane_id: "pane"))
    allow(herdr).to receive(:start).and_raise(IOError)
    op = db[:session_operations][session_id: sid]
    expect(execute(op[:id])).to eq("uncertain")
    recovery = delivery.dup
    allow(recovery).to receive(:body).and_return("@agent recover-session #{op[:id]} pane")
    allow(source).to receive(:call).and_return(Kirei::Services::Result.new(result: recovery))
    live = { "agent_session" => { "source" => "fixture", "agent" => "codex", "kind" => "id", "value" => "conversation" }, "agent_status" => "idle", "interactive_ready" => true, "launch_pending" => false,
             "name" => "digitaltwin-#{sid}", "cwd" => "/workspace/worktrees/workflow", "agent" => "codex" }
    allow(herdr).to receive(:pane).and_return(herdr_pane(live.merge("name" => "different")))
    expect { reconcile(operation_id: op[:id], inbox_id: @inbox, pane_id: "pane") }.to raise_error(ArgumentError)
    allow(herdr).to receive(:pane).and_return(herdr_pane(live))
    2.times { expect(reconcile(operation_id: op[:id], inbox_id: @inbox, pane_id: "pane")).to eq("complete") }
    expect(execute(op[:id])).to eq("complete")
    expect(herdr).to have_received(:start).once
    expect(db[:sessions][id: sid][:runtime_identity]).to eq(live["agent_session"])
  end

  it "reconciles an uncertain stop only from authoritative absence and archives after both stops" do
    workflow(phase: "done")
    control("finish", 0)
    op = db[:session_operations][session_id: "writer", kind: "stop"]
    allow(herdr).to receive(:close).and_raise(IOError)
    expect(execute(op[:id])).to eq("uncertain")
    recovery = delivery.dup
    allow(recovery).to receive(:body).and_return("@agent recover-session #{op[:id]} writer")
    allow(source).to receive(:call).and_return(Kirei::Services::Result.new(result: recovery))
    allow(herdr).to receive(:panes).and_return([Adapters::Herdr::Dto::PaneSummary.new(pane_id: "writer")])
    expect { reconcile(operation_id: op[:id], inbox_id: @inbox, pane_id: "writer") }.to raise_error(ArgumentError)
    allow(herdr).to receive(:panes).and_return([])
    expect(reconcile(operation_id: op[:id], inbox_id: @inbox, pane_id: "writer")).to eq("complete")
    expect(db[:sessions][id: "writer"][:active]).to eq(false)
    expect(db[:workflows].first[:archived_at]).to be_nil
    allow(herdr).to receive(:close)
    reviewer = db[:session_operations][session_id: "reviewer", kind: "stop"]
    expect(execute(reviewer[:id])).to eq("complete")
    expect(db[:workflows].first[:archived_at]).not_to be_nil
  end
  it "reconciles uncertain reviewer prompt from a verified exact review callback without resending" do
    workflow
    id = reviews.ready(token: "writer-token", generation: 1, kind: "spec", commit: commit)
    db[:reviews].where(id: id).update(dispatch_state: "uncertain")
    db[:jobs].where(dispatch_key: "review:#{id}").update(status: "uncertain", effect_started_at: Time.now - 60)
    reviews.finish(token: "reviewer-token", generation: 1, review_commit: review_commit, verdict: "changes_requested")
    expect(db[:reviews][id: id][:dispatch_state]).to eq("delivered")
    expect(db[:workflows].first[:phase]).to eq("spec_writing")
    expect(db[:audit].where(action: "verified_review_prompt_reconciliation").count).to eq(1)
    expect(db[:jobs][dispatch_key: "review:#{id}"][:status]).to eq("complete")
    expect(herdr).not_to have_received(:prompt)
  end

  it "recovers Controller startup only for the first associated human request and exact neutral conversation" do
    config = Domains::Workflows::Dto::RoleConfig.from_hash(roles["writer"].merge("cli" => "gemini", "provider" => "google", "family" => "gemini"))
    master = Domains::Commander::Master.new(db, bootstrap: bootstrap, source: source, herdr: herdr, configuration: config, credential_root: @credential_root, policy: policy)
    master.ingest(@inbox)
    controller = db[:sessions][role: "controller"]
    op = db[:session_operations][session_id: controller[:id]]
    db[:sessions].where(id: controller[:id]).update(pane_id: "controller-pane")
    db[:session_operations].where(id: op[:id]).update(state: "uncertain")
    recovery = delivery.dup
    allow(recovery).to receive(:body).and_return("@agent recover-session #{op[:id]} controller-pane")
    allow(source).to receive(:call).and_return(Kirei::Services::Result.new(result: recovery))
    live = { "agent_session" => { "source" => "fixture", "agent" => "gemini", "kind" => "id", "value" => "conversation" }, "agent_status" => "idle", "interactive_ready" => true, "launch_pending" => false,
             "name" => controller[:alias], "cwd" => "/home/runtime", "agent" => "gemini" }
    allow(herdr).to receive(:pane).and_return(herdr_pane(live))
    expect(reconcile(operation_id: op[:id], inbox_id: @inbox, pane_id: "controller-pane")).to eq("complete")
    expect(db[:sessions][id: controller[:id]][:active]).to eq(true)
    expect(db[:workflows].count).to eq(0)
  end

  describe "worker path (Ruling 12 behavior fixes)" do
    let(:kinds) { Platform::Jobs::Dto::JobKind }
    let(:thread_control) do
      worker_source = double(call: Kirei::Services::Result.new(result: Domains::Messaging::Dto::VerifiedDelivery.new(
        channel_id: channel, thread_id: "t" * 26, post_id: "q" * 26, post_revision: 1, event_kind: Domains::Messaging::Dto::EventKind::Posted, root_post: false, body: "@worker pause",
        actor: Domains::Messaging::Dto::VerifiedActor.new(user_id: "u" * 26, channel_id: channel, member: true, bot: false)
      )))
      Services::Workflows::Control.new(source: worker_source, herdr: herdr, evidence: evidence, reviews: reviews, stop_sessions: stop_sessions)
    end

    def job_status(kind) = db[:jobs][kind: kind.serialize][:status]

    it "dispatches workflow.phase_prompt from a claimed job" do
      workflow
      Domains::Workflows::PhasePrompts.new.enqueue(workflow_id: "workflow", version: 0)
      tick_job(kinds::WorkflowPhasePrompt) { |job| dispatch.call(job: job) }
      expect(job_status(kinds::WorkflowPhasePrompt)).to eq("complete")
      expect(herdr).to have_received(:prompt).once.with(pane_id: "writer", text: a_string_including("Current phase: spec_writing"))
    end

    it "starts a reserved session from a claimed session.start job" do
      workflow(active_sessions: false)
      id = reserve("writer")
      allow(herdr).to receive(:create_workspace).and_return(herdr_workspace(workspace_id: "runtime-workspace", pane_id: "pane"))
      allow(herdr).to receive(:start).and_return(herdr_pane("agent_session" => { "source" => "fixture", "agent" => "codex", "kind" => "id", "value" => "c" }, "agent_status" => "idle"))
      tick_job(kinds::SessionStart) { |job| execute_operation.call(job: job) }
      expect(job_status(kinds::SessionStart)).to eq("complete")
      expect(db[:sessions][id: id][:active]).to be(true)
    end

    it "renews a session from a claimed session.renew job" do
      workflow
      %w[writer reviewer].each { |role| File.write(File.join(@credential_root, "#{role}.token"), "#{role}-token") }
      db[:sessions].update(credential_expires_at: Time.now + 60)
      renewals.schedule_active
      tick_job(kinds::SessionRenew) { |job| renew_service.call(job: job) }
      expect(db[:jobs].where(kind: kinds::SessionRenew.serialize, status: "complete").count).to eq(1)
      expect(db[:sessions].where { credential_expires_at > Time.now + 3000 }.count).to eq(1)
    end

    it "binds a provision request from a claimed workflow.provision job" do
      id = request("Project work")
      tick_job(kinds::WorkflowProvision) { |job| provision.call(job: job) }
      expect(job_status(kinds::WorkflowProvision)).to eq("complete")
      expect(db[:workflow_requests][id: id][:state]).to eq("bound")
    end

    it "applies a router-produced workflow.pause job with a string inbox id" do
      workflow
      payload = Domains::Commander::Dto::InboxDispatchJob.new(inbox_id: @inbox, channel_id: channel, thread_id: "t" * 26, workflow_id: "workflow", expected_version: 0)
      Platform::Jobs::Store.new.enqueue(kind: kinds::WorkflowPause, payload: payload, dispatch_key: "inbox:#{@inbox}:workflow.pause")
      tick_job(kinds::WorkflowPause) { |job| thread_control.call(job: job) }
      expect(job_status(kinds::WorkflowPause)).to eq("complete")
      expect(db[:workflows].first[:phase]).to eq("paused")
    end

    it "applies a master.control job with a string inbox id and audits it" do
      workflow
      payload = Domains::Commander::Dto::MasterControlJob.new(inbox_id: @inbox, workflow_id: "workflow", action: "pause", expected_version: 0)
      Platform::Jobs::Store.new.enqueue(kind: kinds::MasterControl, payload: payload, dispatch_key: "master:control:r:workflow:pause:0")
      tick_job(kinds::MasterControl) { |job| control_service.call(job: job) }
      expect(job_status(kinds::MasterControl)).to eq("complete")
      expect(db[:workflows].first[:phase]).to eq("paused")
      expect(db[:audit][event_key: "workflow:workflow:0:pause"][:details].to_hash).to eq("inbox_id" => @inbox, "workflow_id" => "workflow", "version" => 0)
    end
  end
end

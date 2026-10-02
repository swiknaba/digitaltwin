require_relative "../spec_helper"
RSpec.describe "Master contextual routing (isolated fixtures)" do
  let(:db) { Kirei::App.raw_db_connection }
  let(:channel) { "m" * 26 }
  let(:thread) { "t" * 26 }
  let(:user) { "u" * 26 }
  let(:deliveries) { {} }
  let(:resolver) { double(delivery: nil) }
  let(:membership) { ->(_channel, _user) { true } }
  let(:routing) { Domains::Commander::Routing.new(db, resolver: resolver, membership: membership) }
  let(:ready) {
    { "agent_status" => "idle", "interactive_ready" => true, "launch_pending" => false, "name" => "writer1", "cwd" => "/tmp/w1", "agent" => "codex",
      "agent_session" => { "source" => "fixture", "agent" => "codex", "kind" => "id", "value" => "conversation1" } }
  }
  let(:herdr) { double(pane: herdr_pane(ready), prompt: nil) }
  let(:policy) { double(dispatch_allowed?: true) }
  let(:sender) { Domains::Commander::Followups.new(db, herdr: herdr, resolver: resolver, membership: membership, policy: policy) }

  def source(n = 1, channel_id: channel, thread_id: thread, bot: false, root_post: false, body: "Please also cover that case")
    d = Domains::Mattermost::VerifiedDelivery.new(channel_id: channel_id, thread_id: thread_id, post_id: n.to_s.rjust(26, "p"),
                                                  post_revision: n, event_kind: "posted", root_post: root_post, body: body,
                                                  actor: Domains::Workflows::Entities::Actor.new(channel_id: channel_id, user_id: user, member: true, bot: bot))
    allow(resolver).to receive(:delivery).with(post_id: d.post_id, channel_id: channel_id, event_kind: "posted").and_return(d)
    db[:inbox].insert(channel_id: channel_id, thread_id: thread_id, post_id: d.post_id, post_revision: n,
                      event_kind: "posted", user_id: user, verified_delivery: Sequel.pg_jsonb(d.serialize))
  end

  def workflow(n = 1, phase: "implementation")
    db[:projects].insert(id: "p#{n}", channel_id: n.to_s.rjust(26, "c"), slug: "owner/repo#{n}", remote_identity: "github.com/owner/repo#{n}", workspace: "/tmp/p#{n}")
    db[:workflows].insert(id: "w#{n}", project_id: "p#{n}", channel_id: n.to_s.rjust(26, "c"), thread_id: "root#{n}", branch: "b#{n}", worktree_path: "/tmp/w#{n}", phase: phase)
    db[:sessions].insert(id: "s#{n}", workflow_id: "w#{n}", role: "writer", generation: 1, pane_id: "pane#{n}", alias: "writer#{n}",
                         credential_digest: "digest#{n}", credential_expires_at: Time.now + 3600, configuration: Sequel.pg_jsonb({ "cli" => "codex" }), runtime_identity: Sequel.pg_jsonb({ "source" => "fixture", "agent" => "codex", "kind" => "id", "value" => "conversation#{n}" }))
    "w#{n}"
  end

  it "asks for clarification without guessing a project or creating a session" do
    workflow; workflow(2)
    expect(routing.route(inbox_id: source)[:status]).to eq("clarification")
    expect(db[:followups].count).to eq(0)
    expect(db[:sessions].count).to eq(2)
  end
  it "continues the same session from recent same-human conversation context and deduplicates" do
    workflow
    id = source(body: "@agent route w1\nPlease also cover that case")
    row = routing.route(inbox_id: id, selection: "w1")
    expect(routing.route(inbox_id: id)).to eq(row)
    next_row = routing.route(inbox_id: source(2))
    expect(next_row.values_at(:workflow_id, :session_id, :generation)).to eq(["w1", "s1", 1])
    expect(db[:outbox].count).to eq(2)
    expect(db[:sessions].count).to eq(1)
  end
  it "retains Master context across distinct top-level posts while acknowledging each source thread" do
    workflow; workflow(2)
    master = Domains::Commander::Routing.new(db, resolver: resolver, membership: membership, master_channel_id: channel)
    first_thread = "1".rjust(26, "p")
    second_thread = "2".rjust(26, "p")
    first = source(thread_id: first_thread, root_post: true, body: "@agent route w1\nPlease cover that case")
    master.route(inbox_id: first, selection: "w1")
    second = source(2, thread_id: second_thread, root_post: true)
    row = master.route(inbox_id: second)
    expect(row.values_at(:workflow_id, :session_id, :generation)).to eq(["w1", "s1", 1])
    expect(row[:evidence]["recent_binding"]).to eq(first)
    expect(db[:conversation_bindings][thread_id: "master"]).not_to be_nil
    expect(db[:outbox].order(:response_key).select_map(:thread_id)).to contain_exactly(first_thread, second_thread)
    expect(db[:sessions].count).to eq(2)
  end
  it "uses authoritative project thread mapping" do
    workflow
    row = routing.route(inbox_id: source(channel_id: ("c" * 25) + "1", thread_id: "root1"))
    expect(row[:workflow_id]).to eq("w1")
  end
  it "allows explicit clarification to replace a recent binding but rejects conflicting direct evidence" do
    workflow; workflow(2)
    routing.route(inbox_id: source(body: "@agent route w1\nPlease also cover that case"), selection: "w1")
    expect(routing.route(inbox_id: source(2, body: "@agent route w2\nPlease also cover that case"), selection: "w2")[:workflow_id]).to eq("w2")
    id = source(3, channel_id: ("c" * 25) + "1", thread_id: "root1", body: "@agent route w2\nPlease also cover that case")
    expect(routing.route(inbox_id: id, selection: "w2")[:status]).to eq("clarification")
  end
  it "keeps parallel workflows in one repository on their own threads and sessions" do
    workflow; workflow(2)
    db[:workflows].where(id: "w2").update(project_id: "p1", channel_id: ("c" * 25) + "1")
    db[:projects].where(id: "p2").delete
    expect(routing.route(inbox_id: source(channel_id: ("c" * 25) + "1", thread_id: "root1"))[:session_id]).to eq("s1")
    expect(routing.route(inbox_id: source(2, channel_id: ("c" * 25) + "1", thread_id: "root2"))[:session_id]).to eq("s2")
    expect(db[:workflows].select_map(:worktree_path).uniq.size).to eq(2)
    expect(db[:sessions].count).to eq(2)
  end
  it "expires conversation context" do
    workflow
    routing.route(inbox_id: source(body: "@agent route w1\nPlease also cover that case"), selection: "w1")
    db[:conversation_bindings].update(updated_at: Time.now - 1801)
    expect(routing.route(inbox_id: source(2))[:status]).to eq("clarification")
  end
  it "rejects bot authority and destination membership loss" do
    workflow
    expect { routing.route(inbox_id: source(bot: true), selection: "w1") }.to raise_error(ArgumentError)
    service = Domains::Commander::Routing.new(db, resolver: resolver, membership: ->(*) { false })
    expect { service.route(inbox_id: source(2, body: "@agent route w1\nPlease also cover that case"), selection: "w1") }.to raise_error(ArgumentError)
  end
  it "blocks inactive sessions without replacement" do
    workflow
    db[:sessions].update(active: false)
    expect(routing.route(inbox_id: source(body: "@agent route w1\nPlease also cover that case"), selection: "w1")[:status]).to eq("blocked")
    expect(db[:sessions].count).to eq(1)
  end
  it "blocks missing or multiple active writer sessions without inventing a target" do
    workflow
    db[:sessions].delete
    expect(routing.route(inbox_id: source(body: "@agent route w1\nPlease also cover that case"), selection: "w1")[:status]).to eq("blocked")
    workflow(2)
    current = db[:sessions].first
    db[:sessions].insert(current.merge(id: "duplicate", generation: 2, credential_digest: "duplicate"))
    expect(routing.route(inbox_id: source(2, body: "@agent route w2\nPlease also cover that case"), selection: "w2")[:status]).to eq("blocked")
  end
  it "keeps delivered but unfinished workflows bound without dispatching a new coding phase" do
    workflow(1, phase: "done")
    row = routing.route(inbox_id: source(body: "@agent route w1\nPlease also cover that case"), selection: "w1")
    expect(row[:workflow_id]).to eq("w1")
    expect(sender.deliver(row[:id])).to eq("queued")
    expect(db[:sessions].count).to eq(1)
    expect(herdr).not_to have_received(:prompt)
  end
  it "queues through review and delivers only after release without changing artifacts" do
    workflow(1, phase: "implementation_review")
    row = routing.route(inbox_id: source(body: "@agent route w1\nPlease also cover that case"), selection: "w1")
    before = db[:workflows].first
    expect(sender.deliver(row[:id])).to eq("queued")
    expect(db[:workflows].first).to eq(before)
    expect(herdr).not_to have_received(:prompt)
    db[:workflows].update(phase: "implementation", version: 1)
    expect(sender.deliver(row[:id])).to eq("delivered")
    expect(sender.deliver(row[:id])).to eq("delivered")
    expect(herdr).to have_received(:prompt).once.with(pane_id: "pane1", text: "Please also cover that case")
  end
  it "delivers a busy-session follow-up through worker ticks after the writer becomes idle" do
    workflow
    row = routing.route(inbox_id: source(body: "@agent route w1\nPlease also cover that case"), selection: "w1")
    db[:jobs].where(kind: "mattermost.post").update(status: "complete")
    allow(herdr).to receive(:pane).and_return(herdr_pane(ready.merge("agent_status" => "working")))
    worker = Platform::Jobs::Worker.new(handlers: { Platform::Jobs::Dto::JobKind::SessionFollowup => Platform::Jobs::CallableHandler.new(->(job) { sender.call(job: job) }) })
    Async { expect(worker.tick).to eq(true) }.wait
    job = db[:jobs][kind: "session.followup"]
    expect(job[:status]).to eq("pending")
    expect(job[:attempts]).to eq(0)
    expect(job[:effect_started_at]).to be_nil
    expect(job[:available_at]).to be > Time.now
    expect(db[:followups][id: row[:id]][:status]).to eq("queued")
    expect(herdr).not_to have_received(:prompt)
    allow(herdr).to receive(:pane).and_return(herdr_pane(ready))
    db[:jobs].where(id: job[:id]).update(available_at: Time.now - 1)
    Async { expect(worker.tick).to eq(true) }.wait
    expect(db[:jobs][id: job[:id]][:status]).to eq("complete")
    expect(db[:followups][id: row[:id]][:status]).to eq("delivered")
    expect(herdr).to have_received(:prompt).once.with(pane_id: "pane1", text: "Please also cover that case")
    Async { expect(worker.tick).to eq(false) }.wait
  end
  it "keeps a review-locked worker job retryable and delivers after writing resumes" do
    workflow(1, phase: "implementation_review")
    row = routing.route(inbox_id: source(body: "@agent route w1\nPlease also cover that case"), selection: "w1")
    db[:jobs].where(kind: "mattermost.post").update(status: "complete")
    before = db[:workflows][id: "w1"]
    worker = Platform::Jobs::Worker.new(handlers: { Platform::Jobs::Dto::JobKind::SessionFollowup => Platform::Jobs::CallableHandler.new(->(job) { sender.call(job: job) }) })
    Async { expect(worker.tick).to eq(true) }.wait
    job = db[:jobs][kind: "session.followup"]
    expect(job[:status]).to eq("pending")
    expect(job[:effect_started_at]).to be_nil
    expect(db[:workflows][id: "w1"]).to eq(before)
    expect(herdr).not_to have_received(:pane)
    expect(herdr).not_to have_received(:prompt)
    db[:workflows].where(id: "w1").update(phase: "implementation", version: 1)
    db[:jobs].where(id: job[:id]).update(available_at: Time.now - 1)
    Async { expect(worker.tick).to eq(true) }.wait
    expect(db[:jobs][id: job[:id]][:status]).to eq("complete")
    expect(db[:followups][id: row[:id]][:status]).to eq("delivered")
    expect(herdr).to have_received(:prompt).once.with(pane_id: "pane1", text: "Please also cover that case")
  end
  it "keeps production dispatch gated" do
    workflow
    row = routing.route(inbox_id: source(body: "@agent route w1\nPlease also cover that case"), selection: "w1")
    gated = Domains::Commander::Followups.new(db, herdr: herdr, resolver: resolver, membership: membership)
    expect(gated.deliver(row[:id])).to eq("queued")
    expect(herdr).not_to have_received(:pane)
  end
  it "does not resend an uncertain effect or overtake it" do
    workflow
    one = routing.route(inbox_id: source(body: "@agent route w1\nPlease also cover that case"), selection: "w1")
    two = routing.route(inbox_id: source(2))
    allow(herdr).to receive(:prompt).and_raise(IOError)
    expect(sender.deliver(one[:id])).to eq("uncertain")
    expect(sender.deliver(one[:id])).to eq("uncertain")
    expect(sender.deliver(two[:id])).to eq("queued")
    expect(herdr).to have_received(:prompt).once
  end
  it "rechecks generation and unknown live state" do
    workflow
    row = routing.route(inbox_id: source(body: "@agent route w1\nPlease also cover that case"), selection: "w1")
    db[:sessions].update(generation: 2)
    expect(sender.deliver(row[:id])).to eq("blocked")
    row = routing.route(inbox_id: source(2))
    allow(herdr).to receive(:pane).and_return(herdr_pane("agent_status" => "unknown"))
    expect(sender.deliver(row[:id])).to eq("blocked")
    expect(herdr).not_to have_received(:prompt)
  end
  it "serializes concurrent inbox routing and concurrent sends without duplicate effects" do
    workflow
    id = source(body: "@agent route w1\nPlease also cover that case")
    Async do |task|
      tasks = 2.times.map { task.async { routing.route(inbox_id: id, selection: "w1") } }
      tasks.each(&:wait)
    end.wait
    expect(db[:followups].count).to eq(1)
    row = db[:followups].first
    allow(herdr).to receive(:prompt) { Async::Task.current.sleep(0.05) }
    Async do |task|
      tasks = 2.times.map { task.async { sender.deliver(row[:id]) } }
      tasks.each(&:wait)
    end.wait
    expect(herdr).to have_received(:prompt).once
    expect(db[:followups].first[:status]).to eq("delivered")
  end
  it "does not send to a substituted live pane conversation" do
    workflow
    row = routing.route(inbox_id: source(body: "@agent route w1\nPlease also cover that case"), selection: "w1")
    allow(herdr).to receive(:pane).and_return(herdr_pane("agent_status" => "idle", "interactive_ready" => true, "launch_pending" => false,
                                                         "name" => "another-session", "cwd" => "/tmp/w1", "agent" => "codex"))
    expect(sender.deliver(row[:id])).to eq("blocked")
    expect(herdr).not_to have_received(:prompt)
  end
  it "rejects a replacement conversation even when its pane alias directory and CLI are unchanged" do
    workflow
    row = routing.route(inbox_id: source(body: "@agent route w1\nPlease also cover that case"), selection: "w1")
    allow(herdr).to receive(:pane).and_return(herdr_pane(ready.merge("agent_session" => ready.fetch("agent_session").merge("value" => "replacement"))))
    expect(sender.deliver(row[:id])).to eq("blocked")
    expect(db[:followups][id: row[:id]][:status]).to eq("blocked")
    expect(herdr).not_to have_received(:prompt)
  end
  it "keeps a busy session queued and rechecks membership before delivery" do
    workflow
    row = routing.route(inbox_id: source(body: "@agent route w1\nPlease also cover that case"), selection: "w1")
    allow(herdr).to receive(:pane).and_return(herdr_pane(ready.merge("agent_status" => "working")))
    expect(sender.deliver(row[:id])).to eq("queued")
    denied = Domains::Commander::Followups.new(db, herdr: herdr, resolver: resolver, membership: ->(*) { false }, policy: policy)
    expect(denied.deliver(row[:id])).to eq("blocked")
    expect(herdr).not_to have_received(:prompt)
  end
  it "rejects a changed authenticated source before routing" do
    workflow
    id = source
    db[:inbox].where(id: id).update(post_revision: 999)
    expect { routing.route(inbox_id: id) }.to raise_error(ArgumentError, "Source changed")
  end
  it "does not retarget an existing queued message to another workflow" do
    workflow; workflow(2)
    id = source(body: "@agent route w1\nPlease also cover that case")
    row = routing.route(inbox_id: id, selection: "w1")
    expect(routing.route(inbox_id: id, selection: "w2")[:workflow_id]).to eq(row[:workflow_id])
  end
  it "accepts ordinary verified human messages in the configured Master channel" do
    id = source
    d = resolver.delivery(post_id: db[:inbox][id: id][:post_id], channel_id: channel, event_kind: "posted")
    db[:inbox].delete
    Domains::Mattermost::Router.new(db, master_channel_id: channel).ingest(delivery: d)
    expect(db[:jobs].first[:kind]).to eq("master.prompt")
  end
  it "records exact Master-chat approval only for the latest reviewed current revision" do
    workflow(1, phase: "spec_human_approval")
    commit = "a" * 40
    db[:reviews].insert(workflow_id: "w1", gate: "spec", round: 1, target_commit: commit, verdict: "approve", review_path: "review.md", reviewer_configuration: Sequel.pg_jsonb({ "cli" => "codex" }))
    approvals = Domains::Commander::Approvals.new(db, resolver: resolver, membership: membership, current_commit: ->(_worktree) { commit })
    id = source(body: "@agent approve w1 spec #{commit}")
    args = { inbox_id: id, workflow_id: "w1", gate: "spec", commit: commit }
    approvals.record(**args)
    approvals.record(**args)
    expect(db[:approvals].count).to eq(1)
    expect(db[:approvals].first[:channel_id]).to eq(channel)
    expect { approvals.record(**args.merge(commit: "b" * 40)) }.to raise_error(ArgumentError)
    expect { approvals.record(**args.merge(commit: "approve")) }.to raise_error(ArgumentError)
  end
  it "grounds semantic interpretation in accessible recent task evidence" do
    workflow; workflow(2)
    cited = source(channel_id: ("c" * 25) + "1", thread_id: "root1", body: "We should cover retries")
    request = source(2, body: "Add that retry behavior please")
    row = routing.route(inbox_id: request, interpretation: { "workflow_id" => "w1", "evidence_inbox_ids" => [cited] })
    expect(row[:session_id]).to eq("s1")
    expect { routing.route(inbox_id: source(3), interpretation: { "workflow_id" => "w2", "evidence_inbox_ids" => [cited] }) }.to raise_error(ArgumentError)
  end

  it "preserves parallel Master reply bindings when another root changes current context" do
    workflow; workflow(2)
    master = Domains::Commander::Routing.new(db, resolver: resolver, membership: membership, master_channel_id: channel)
    master.route(inbox_id: source(root_post: true, thread_id: "master-a", body: "@agent route w1\nFirst task"), selection: "w1")
    master.route(inbox_id: source(2, root_post: true, thread_id: "master-b", body: "@agent route w2\nSecond task"), selection: "w2")
    expect(master.route(inbox_id: source(3, thread_id: "master-a"))[:workflow_id]).to eq("w1")
    expect(master.route(inbox_id: source(4, thread_id: "new-root", root_post: true))[:workflow_id]).to eq("w2")
  end
  it "queues a follow-up against a reserved starting conversation and delivers after activation" do
    workflow
    db[:sessions].where(id: "s1").update(active: false)
    db[:session_operations].insert(id: "start", session_id: "s1", kind: "start")
    row = routing.route(inbox_id: source(body: "@agent route w1\nStartup instruction"), selection: "w1")
    expect(row.values_at(:status, :session_id, :generation)).to eq(["queued", "s1", 1])
    expect(sender.deliver(row[:id])).to eq("queued")
    db[:session_operations].where(id: "start").update(state: "uncertain")
    expect(sender.deliver(row[:id])).to eq("queued")
    expect(db[:followups][id: row[:id]][:status]).to eq("queued")
    expect(herdr).not_to have_received(:prompt)
    db[:sessions].where(id: "s1").update(active: true)
    db[:session_operations].where(id: "start").update(state: "complete")
    expect(sender.deliver(row[:id])).to eq("delivered")
    expect(db[:sessions].count).to eq(1)
  end

  it "waits for same-conversation credential renewal instead of losing the instruction" do
    workflow
    db[:sessions].where(id: "s1").update(credential_expires_at: Time.now - 1)
    row = routing.route(inbox_id: source(body: "@agent route w1\nRenewal instruction"), selection: "w1")
    expect(row.values_at(:status, :session_id)).to eq(["queued", "s1"])
    expect(sender.deliver(row[:id])).to eq("queued")
    expect(db[:jobs].where(kind: "session.renew").count).to eq(1)
    db[:sessions].where(id: "s1").update(credential_expires_at: Time.now + 3600)
    expect(sender.deliver(row[:id])).to eq("delivered")
  end

  it "requires exact human outcome reconciliation before advancing past an uncertain send" do
    workflow
    row = routing.route(inbox_id: source(body: "@agent route w1\nFirst instruction"), selection: "w1")
    allow(herdr).to receive(:prompt).and_raise(IOError)
    expect(sender.deliver(row[:id])).to eq("uncertain")
    later = routing.route(inbox_id: source(2, body: "Second instruction"))
    expect(sender.deliver(later[:id])).to eq("queued")
    recovery = source(3, body: "@agent recover-followup #{row[:id]} discard")
    expect(sender.reconcile(id: row[:id], inbox_id: recovery, outcome: "discard")).to eq("discard")
    expect(sender.reconcile(id: row[:id], inbox_id: recovery, outcome: "discard")).to eq("discard")
    expect(db[:followups][id: row[:id]][:status]).to eq("blocked")
    expect(db[:audit].where(action: "human_followup_reconciliation").count).to eq(1)
    allow(herdr).to receive(:prompt)
    expect(sender.deliver(later[:id])).to eq("delivered")
    expect(herdr).to have_received(:prompt).with(pane_id: "pane1", text: "First instruction").once
    expect(herdr).to have_received(:prompt).with(pane_id: "pane1", text: "Second instruction").once
  end

  it "rejects bot, changed outcome, live send leases and replaced conversation recovery" do
    workflow
    row = routing.route(inbox_id: source(body: "@agent route w1\nInstruction"), selection: "w1")
    db[:followups].where(id: row[:id]).update(status: "uncertain")
    bot = source(2, bot: true, body: "@agent recover-followup #{row[:id]} delivered")
    expect { sender.reconcile(id: row[:id], inbox_id: bot, outcome: "delivered") }.to raise_error(ArgumentError)
    recovery = source(3, body: "@agent recover-followup #{row[:id]} delivered")
    job = db[:jobs][dispatch_key: "followup:#{row[:id]}"]
    db[:jobs].where(id: job[:id]).update(status: "running", lease_expires_at: Time.now + 30)
    expect { sender.reconcile(id: row[:id], inbox_id: recovery, outcome: "delivered") }.to raise_error(ArgumentError)
    db[:jobs].where(id: job[:id]).update(status: "uncertain")
    allow(herdr).to receive(:pane).and_return(herdr_pane(ready.merge("agent_session" => { "value" => "replacement" })))
    expect { sender.reconcile(id: row[:id], inbox_id: recovery, outcome: "delivered") }.to raise_error(ArgumentError)
    allow(herdr).to receive(:pane).and_return(herdr_pane(ready))
    expect(sender.reconcile(id: row[:id], inbox_id: recovery, outcome: "delivered")).to eq("delivered")
    expect(herdr).not_to have_received(:prompt)
    other = source(4, body: "@agent recover-followup #{row[:id]} discard")
    expect { sender.reconcile(id: row[:id], inbox_id: other, outcome: "discard") }.to raise_error(ArgumentError)
  end
  it "routes an exact recovery command in Master chat before model interpretation" do
    workflow
    row = routing.route(inbox_id: source(body: "@agent route w1\nInstruction"), selection: "w1")
    db[:followups].where(id: row[:id]).update(status: "uncertain")
    recovery = source(2, body: "@agent recover-followup #{row[:id]} discard")
    services = Domains::Commander::Services.allocate
    services.instance_variable_set(:@source, Domains::Commander::Source.new(db, resolver: resolver, membership: membership))
    services.instance_variable_set(:@followups, sender)
    inbox = db[:inbox][id: recovery]
    Platform::Jobs::Store.new.enqueue(kind: Platform::Jobs::Dto::JobKind::MasterPrompt, dispatch_key: "inbox:#{recovery}:master.prompt",
                                      payload: Domains::Commander::Dto::InboxDispatchJob.new(inbox_id: recovery, channel_id: inbox[:channel_id], thread_id: inbox[:thread_id]))
    expect(services.route(job: claim_job(Platform::Jobs::Dto::JobKind::MasterPrompt))).to eq(Platform::Jobs::Dto::Decision.complete)
    expect(db[:followups][id: row[:id]][:status]).to eq("blocked")
    expect(herdr).not_to have_received(:prompt)
  end
end

# typed: strict
# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe Platform::Jobs::Store do
  let(:db) { Kirei::App.raw_db_connection }
  let(:store) { described_class.new }
  let(:kind) { Platform::Jobs::Dto::JobKind::MattermostPost }

  def enqueue(key = "one", outbox_id: "x")
    store.enqueue(kind: kind, payload: Domains::Messaging::Dto::OutboxPostJob.new(outbox_id: outbox_id), dispatch_key: key)
  end

  it "enqueue is idempotent per dispatch key and rejects changed payload" do
    expect(enqueue).to eq(enqueue)
    expect(db[:jobs].count).to eq(1)
    expect(db[:jobs].first[:payload].to_hash).to eq("outbox_id" => "x")
    expect { enqueue(outbox_id: "changed") }.to raise_error(Platform::Jobs::Errors::DispatchKeyReused, "Dispatch key reused with changed content")
    other_kind = Platform::Jobs::Dto::JobKind::ReviewRelease
    expect { store.enqueue(kind: other_kind, payload: Domains::Messaging::Dto::OutboxPostJob.new(outbox_id: "x"), dispatch_key: "one") }
      .to raise_error(Platform::Jobs::Errors::DispatchKeyReused)
  end

  it "persists payload structs without nil props and parses them strictly" do
    payload = Domains::Commander::Dto::InboxDispatchJob.new(inbox_id: "inbox_7", channel_id: "c", thread_id: "t")
    store.enqueue(kind: Platform::Jobs::Dto::JobKind::MasterPrompt, payload: payload, dispatch_key: "inbox:7:master.prompt")
    persisted = db[:jobs].first[:payload].to_hash
    expect(persisted).to eq("inbox_id" => "inbox_7", "channel_id" => "c", "thread_id" => "t")
    expect(Domains::Commander::Dto::InboxDispatchJob.from_hash(persisted, true)).to eq(payload)
    expect { Domains::Commander::Dto::InboxDispatchJob.from_hash(persisted.merge("unknown" => 1), true) }.to raise_error(RuntimeError, /unknown/)
  end

  it "claims exclusively with concurrent workers" do
    enqueue
    jobs = 2.times.map { |i| Thread.new { store.claim(worker_id: i.to_s, now: Time.now) } }.map(&:value).compact
    expect(jobs.size).to eq(1)
    expect(jobs.first.kind).to eq(kind)
    expect(jobs.first.payload).to eq("outbox_id" => "x")
    expect(jobs.first.attempts).to eq(1)
  end

  it "reclaims expired uneffected leases but rejects old completion tokens" do
    id = enqueue
    now = Time.now
    a = store.claim(worker_id: "a", now: now)
    b = store.claim(worker_id: "b", now: now + 31)
    expect(b.id).to eq(id)
    expect(store.complete(id: id, lease_token: a.lease.token)).to be(false)
    expect(store.complete(id: id, lease_token: b.lease.token)).to be(true)
  end

  it "blocks on the fifth failure" do
    id = enqueue
    now = Time.now
    5.times do |i|
      job = store.claim(worker_id: "a", now: now + (i * 100))
      store.retry(id: id, lease_token: job.lease.token, error: "fixture", now: now + (i * 100))
    end
    expect(db[:jobs][id: id][:status]).to eq("blocked")
  end

  it "blocks a crash after beginning an external effect, without retrying it" do
    enqueue
    now = Time.now
    job = store.claim(worker_id: "a", now: now)
    expect(job.lease.begin_effect(now: now)).to be(true)
    expect(store.claim(worker_id: "b", now: now + 31)).to be_nil
    expect(db[:jobs][id: job.id][:status]).to eq("uncertain")
  end

  it "begin_effect returns false after lease expiry" do
    enqueue
    now = Time.now
    job = store.claim(worker_id: "a", now: now)
    expect(job.lease.begin_effect(now: now + 31)).to be(false)
    expect(db[:jobs][id: job.id][:effect_started_at]).to be_nil
  end

  it "heartbeats only the current lease" do
    enqueue
    job = store.claim(worker_id: "a", now: Time.now)
    expect(store.heartbeat(id: job.id, lease_token: "wrong")).to be(false)
    expect(job.lease.heartbeat).to be(true)
  end

  it "unstarted? matches only effect-free pending or blocked jobs" do
    phase = Platform::Jobs::Dto::JobKind::WorkflowPhasePrompt
    queue = ->(workflow_id, version) do
      store.enqueue(kind: phase, payload: Domains::Workflows::Dto::PhasePromptJob.new(workflow_id: workflow_id, version: version), dispatch_key: "workflow:phase:#{workflow_id}:#{version}")
    end
    expect(store.unstarted?(kind: phase, field: "workflow_id", value: "w1")).to be(false)
    id = queue.call("w1", 1)
    expect(store.unstarted?(kind: phase, field: "workflow_id", value: "w1")).to be(true)
    expect(store.unstarted?(kind: phase, field: "workflow_id", value: "w2")).to be(false)
    expect(store.unstarted?(kind: kind, field: "workflow_id", value: "w1")).to be(false)
    db[:jobs].where(id: id).update(status: "blocked")
    expect(store.unstarted?(kind: phase, field: "workflow_id", value: "w1")).to be(true)
    db[:jobs].where(id: id).update(effect_started_at: Time.now)
    expect(store.unstarted?(kind: phase, field: "workflow_id", value: "w1")).to be(false)
    db[:jobs].where(id: id).update(effect_started_at: nil, status: "running")
    expect(store.unstarted?(kind: phase, field: "workflow_id", value: "w1")).to be(false)
  end

  it "finds snapshots by id and dispatch key" do
    id = enqueue
    snapshot = store.find_by_key(dispatch_key: "one")
    expect(snapshot).to eq(store.find(id: id))
    expect(snapshot.status).to eq(Platform::Jobs::Dto::JobStatus::Pending)
    expect(store.find_by_key(dispatch_key: "missing")).to be_nil
  end

  it "requeues only blocked effect-free jobs with a fresh attempt budget" do
    id = enqueue
    expect(store.requeue_blocked(id: id)).to be(false)
    db[:jobs].where(id: id).update(status: "blocked", attempts: 5, last_error: "gated", available_at: Time.now + 3600)
    expect(store.requeue_blocked(id: id)).to be(true)
    expect(db[:jobs][id: id].values_at(:status, :attempts, :last_error)).to eq(["pending", 0, nil])
    db[:jobs].where(id: id).update(status: "blocked", effect_started_at: Time.now)
    expect(store.requeue_blocked(id: id)).to be(false)
  end

  it "closes uncertain jobs only, and reconciled jobs in any status" do
    id = enqueue
    expect(store.close_uncertain(id: id)).to be(false)
    db[:jobs].where(id: id).update(status: "uncertain", lease_token: "t")
    expect(store.close_uncertain(id: id)).to be(true)
    expect(db[:jobs][id: id].values_at(:status, :lease_token)).to eq(["complete", nil])
    db[:jobs].where(id: id).update(status: "running", lease_token: "t", lease_expires_at: Time.now + 30)
    store.close_reconciled(id: id)
    expect(db[:jobs][id: id].values_at(:status, :lease_token, :lease_expires_at)).to eq(["complete", nil, nil])
  end

  it "rolls back state and outbox together" do
    expect {
      db.transaction {
        enqueue
        message = Domains::Messaging::Dto::OutgoingMessage.new(channel_id: "c", thread_id: "r", bot: Domains::Messaging::Dto::Bot::Worker,
                                                               role: Domains::Messaging::Dto::SpeakerRole::Writer, body: "hello", key: "response")
        Domains::Messaging::Outbox.new.enqueue(message: message)
        raise "abort"
      }
    }.to raise_error("abort")
    expect(db[:jobs].count).to eq(0)
    expect(db[:outbox].count).to eq(0)
  end

  it "deduplicates responses and rejects changed bodies" do
    outbox = Domains::Messaging::Outbox.new
    args = { channel_id: "c", thread_id: "r", bot: Domains::Messaging::Dto::Bot::Worker, role: Domains::Messaging::Dto::SpeakerRole::Writer, body: "hello", key: "response" }
    message = ->(**changes) { Domains::Messaging::Dto::OutgoingMessage.new(**args.merge(changes)) }
    expect(outbox.enqueue(message: message.call).result).to eq(outbox.enqueue(message: message.call).result)
    expect(outbox.enqueue(message: message.call(body: "changed")).errors.first&.detail).to eq("Response key reused with changed content")
    expect(db[:jobs].count).to eq(1)
  end
end

RSpec.describe Platform::Jobs::Worker do
  let(:db) { Kirei::App.raw_db_connection }
  let(:store) { Platform::Jobs::Store.new }
  let(:kind) { Platform::Jobs::Dto::JobKind::MattermostPost }

  def tick_with(decision)
    id = store.enqueue(kind: kind, payload: Domains::Messaging::Dto::OutboxPostJob.new(outbox_id: "x"), dispatch_key: "one")
    handler = Platform::Jobs::CallableHandler.new(->(_job) { decision })
    Async { expect(described_class.new(handlers: { kind => handler }).tick).to be(true) }.wait
    db[:jobs][id: id]
  end

  it "handler decisions map to complete/defer/block" do
    expect(tick_with(Platform::Jobs::Dto::Decision.complete)[:status]).to eq("complete")
    db[:jobs].delete
    deferred = tick_with(Platform::Jobs::Dto::Decision.defer("later"))
    expect(deferred.values_at(:status, :attempts, :last_error)).to eq(["pending", 0, "later"])
    db[:jobs].delete
    blocked = tick_with(Platform::Jobs::Dto::Decision.block("gated"))
    expect(blocked.values_at(:status, :last_error, :lease_token)).to eq(["blocked", "gated", nil])
  end

  it "completes a defer decision when the effect already began" do
    id = store.enqueue(kind: kind, payload: Domains::Messaging::Dto::OutboxPostJob.new(outbox_id: "x"), dispatch_key: "one")
    handler = Platform::Jobs::CallableHandler.new(lambda do |job|
      job.lease.begin_effect
      Platform::Jobs::Dto::Decision.defer("too late")
    end)
    Async { described_class.new(handlers: { kind => handler }).tick }.wait
    expect(db[:jobs][id: id][:status]).to eq("complete")
  end

  it "blocks jobs without a configured handler" do
    id = store.enqueue(kind: kind, payload: Domains::Messaging::Dto::OutboxPostJob.new(outbox_id: "x"), dispatch_key: "one")
    Async { expect(described_class.new.tick).to be(true) }.wait
    expect(db[:jobs][id: id][:status]).to eq("blocked")
  end
end

# frozen_string_literal: true

require "spec_helper"
require "json"
require "openssl"
require "socket"

class RecordingCommanderGateway
  include Adapters::OpenCode::Gateway

  attr_reader :deliveries, :outcomes

  def initialize
    @deliveries = []
    @outcomes = []
  end

  def deliver(task_id:, text:, references:, due_at:, timezone:, origin:, attempt:, delivery_key:)
    @deliveries << { task_id:, text:, references:, due_at:, timezone:, origin:, attempt:, delivery_key: }
    Domains::FutureTasks::Dto::DeliveryReceipt.new(delivery_key:, commander_item_id: "commander-item-#{@deliveries.length}")
  end

  def reconcile(delivery_key:)
    Domains::FutureTasks::Dto::BridgeResolution.new(receipt: Domains::FutureTasks::Dto::DeliveryReceipt.new(delivery_key:, commander_item_id: "commander-item-reconciled"))
  end

  def record_outcome(delivery_key:, outcome:)
    @outcomes << { delivery_key:, outcome: }
  end
end

class UncertainThenReconciledGateway < RecordingCommanderGateway
  def initialize
    super
    @first_delivery = true
  end

  def deliver(task_id:, text:, references:, due_at:, timezone:, origin:, attempt:, delivery_key:)
    if @first_delivery
      @first_delivery = false
      raise IOError, "bridge result lost"
    end

    super
  end
end

class UncertainThenRedeliveredGateway < UncertainThenReconciledGateway
  def reconcile(**)
    Domains::FutureTasks::Dto::BridgeResolution.new
  end
end

class OutcomeFailsOnceGateway < RecordingCommanderGateway
  def initialize
    super
    @first_outcome = true
  end

  def record_outcome(delivery_key:, outcome:)
    if @first_outcome
      @first_outcome = false
      raise IOError, "bridge temporarily unavailable"
    end

    super
  end
end

class FailingAfterEnqueueStore < Platform::Jobs::Store
  def enqueue(kind:, payload:, dispatch_key:, available_at: Time.now)
    super
    raise "force transaction rollback"
  end
end

RSpec.describe Domains::FutureTasks::Tasks do
  let(:tasks) { described_class.new }
  let(:now) { Time.utc(2026, 10, 13, 12, 0, 0) }

  def create_task(key: "create-1", due_at: now + 60)
    tasks.create(actor_id: "operator-1", origin: "commander:main", idempotency_key: key, text: "Review the deployment plan", due_at:, timezone: "UTC",
                 local_time: due_at.utc.iso8601, references: ["repo:digitaltwin"], now:)
  end

  def capability(secret:, id:, actor: "operator-1", conversation: "commander:main", owner: false, issued_at: Time.now, expires_at: Time.now + 300)
    payload = { "jti" => id, "actor" => actor, "conversation" => conversation, "aud" => "future_tasks", "iat" => issued_at.to_i, "exp" => expires_at.to_i, "owner" => owner }.to_json.unpack1("H*")
    "#{payload}.#{OpenSSL::HMAC.hexdigest("SHA256", secret, payload)}"
  end

  def opencode_response(body: "{}", status: 200)
    server = TCPServer.new("127.0.0.1", 0)
    received = Queue.new
    thread = Thread.new do
      client = server.accept
      received << client.readpartial(4096)
      client.write("HTTP/1.1 #{status} OK\r\nContent-Type: application/json\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
      client.close
      server.close
    end
    ["http://127.0.0.1:#{server.addr[1]}", thread, received]
  end

  it "creates one current execution for an actor-scoped idempotency key" do
    first = create_task
    second = create_task

    expect(second).to eq(first)
    delayed_retry = tasks.create(actor_id: "operator-1", origin: "commander:main", idempotency_key: "create-1", text: "Review the deployment plan", due_at: now + 60,
                                 timezone: "UTC", local_time: (now + 60).utc.iso8601, references: ["repo:digitaltwin"], now: now + 120)
    expect(delayed_retry).to eq(first)
    expect(Kirei::App.raw_db_connection[:future_tasks].count).to eq(1)
    expect { create_task(due_at: now + 120) }.to raise_error(ArgumentError, /Idempotency key reused/)
  end

  it "deduplicates a one-time successor created by a due-task retry" do
    parent = create_task(key: "weekly-parent")
    successor_due_at = now + (7 * 24 * 60 * 60)
    first = tasks.create(
      actor_id: "operator-1", origin: "commander:main", idempotency_key: "successor:#{parent.id}:1", text: "Review the deployment plan", due_at: successor_due_at,
      timezone: "UTC", local_time: successor_due_at.utc.iso8601, references: ["repo:digitaltwin"], now: now + 60
    )
    retried = tasks.create(
      actor_id: "operator-1", origin: "commander:main", idempotency_key: "successor:#{parent.id}:1", text: "Review the deployment plan", due_at: successor_due_at,
      timezone: "UTC", local_time: successor_due_at.utc.iso8601, references: ["repo:digitaltwin"], now: now + 120
    )

    expect(retried).to eq(first)
    expect(Kirei::App.raw_db_connection[:future_tasks].count).to eq(2)
  end

  it "uses an opaque created-at/id cursor and rejects malformed capability timing" do
    first = create_task(key: "page-1", due_at: now + 60)
    second = create_task(key: "page-2", due_at: now + 120)
    secret = "test-capability-secret"
    api = Services::FutureTasks::CapabilityApi.new(tasks:, verifier: Adapters::FutureTasks::CapabilityVerifier.new(secret:))
    page = api.list(token: capability(secret:, id: "page-token"), limit: 1)

    expected = [first, second].sort_by { |task| [task.created_at, task.id] }
    expect(page.items).to eq([expected.fetch(0)])
    expect(page.next_cursor).not_to eq(expected.fetch(0).id)
    expect(api.list(token: capability(secret:, id: "page-token-2"), cursor: page.next_cursor, limit: 1).items).to eq([expected.fetch(1)])
    expect { api.list(token: capability(secret:, id: "future", issued_at: Time.now + 60), limit: 1) }.to raise_error(ArgumentError, "Capability issued in the future")
    expect { api.list(token: capability(secret:, id: "long", issued_at: Time.now - 1, expires_at: Time.now + 301), limit: 1) }.to raise_error(ArgumentError, "Capability lifetime is invalid")
  end

  it "rolls back a queued job with its task when persistence fails after enqueue" do
    failing = described_class.new(jobs: FailingAfterEnqueueStore.new)
    expect { failing.create(actor_id: "operator-1", idempotency_key: "rollback", text: "Check", due_at: now + 60, timezone: "UTC", local_time: (now + 60).utc.iso8601, now:) }.to raise_error(RuntimeError, "force transaction rollback")
    database = Kirei::App.raw_db_connection
    expect(database[:future_tasks].count).to eq(0)
    expect(database[:future_task_executions].count).to eq(0)
    expect(database[:jobs].count).to eq(0)
  end

  it "returns one matching task when concurrent callers reuse an idempotency key" do
    ready = Queue.new
    start = Queue.new
    outcomes = 2.times.map do
      Thread.new do
        ready << true
        start.pop
        create_task(key: "concurrent-create")
      end
    end
    2.times { ready.pop }
    2.times { start << true }
    tasks_created = outcomes.map(&:value)
    expect(tasks_created.map(&:id).uniq).to have_attributes(length: 1)
    expect(Kirei::App.raw_db_connection[:future_tasks].count).to eq(1)
    expect(Kirei::App.raw_db_connection[:jobs].count).to eq(1)
  end

  it "updates or cancels only an unstarted expected version and stales its prior execution" do
    task = create_task
    updated = tasks.update(actor_id: "operator-1", id: task.id, expected_version: 1, text: "Review the revised plan", due_at: now + 120,
                           timezone: "UTC", local_time: (now + 120).utc.iso8601, now:)

    expect(updated.version).to eq(2)
    expect(updated.text).to eq("Review the revised plan")
    expect { tasks.cancel(actor_id: "operator-1", id: task.id, expected_version: 1, now:) }.to raise_error(ArgumentError, /version is stale/)
    canceled = tasks.cancel(actor_id: "operator-1", id: task.id, expected_version: 2, now:)
    expect(canceled.state).to eq(Domains::FutureTasks::Dto::TaskState::Canceled)
  end

  it "delivers a due check-in once and records an explicit disposition without starting project work" do
    task = create_task(due_at: now + 1)
    Kirei::App.raw_db_connection[:jobs].update(available_at: Time.now - 1)
    gateway = RecordingCommanderGateway.new
    handler = Services::FutureTasks::DeliverDue.new(tasks:, gateway:)

    Async { Platform::Jobs::Worker.new(handlers: { Platform::Jobs::Dto::JobKind::FutureTaskDue => handler }).tick }.wait
    delivered = tasks.find(actor_id: "operator-1", id: task.id)

    expect(gateway.deliveries).to have_attributes(length: 1)
    expect(delivered.state).to eq(Domains::FutureTasks::Dto::TaskState::AwaitingDisposition)
    expect(delivered.receipt).to have_attributes(delivery_key: task.delivery_key, commander_item_id: "commander-item-1")

    secret = "test-capability-secret"
    api = Services::FutureTasks::CapabilityApi.new(tasks:, verifier: Adapters::FutureTasks::CapabilityVerifier.new(secret:))
    completed = api.record_disposition(token: capability(secret:, id: "disposition-1"), id: task.id, expected_version: 1, disposition_key: "answer-1",
                                       outcome: "project_work_requested")
    expect(completed.state).to eq(Domains::FutureTasks::Dto::TaskState::Completed)
    expect(completed.outcome).to eq("project_work_requested")
    retried = api.record_disposition(token: capability(secret:, id: "disposition-2"), id: task.id, expected_version: 1, disposition_key: "answer-1",
                                     outcome: "project_work_requested")
    expect(retried.state).to eq(Domains::FutureTasks::Dto::TaskState::Completed)
    expect { api.record_disposition(token: capability(secret:, id: "disposition-3"), id: task.id, expected_version: 1, disposition_key: "answer-1", outcome: "assessed") }.to raise_error(ArgumentError, /changed body/)
    expect(Kirei::App.raw_db_connection[:future_task_dispositions].first[:outcome]).to eq("project_work_requested")
    outcome_job = Platform::Jobs::Store.new.find_by_key(dispatch_key: "future-task-outcome:#{task.delivery_key}:project_work_requested")
    expect(outcome_job).not_to be_nil
    expect(gateway.outcomes).to be_empty
  end

  it "persists a disposition outcome in the outbox and retries a bridge outage with the same delivery key" do
    task = create_task(due_at: now + 1)
    Kirei::App.raw_db_connection[:jobs].update(available_at: Time.now - 1)
    delivery_gateway = RecordingCommanderGateway.new
    Async { Platform::Jobs::Worker.new(handlers: { Platform::Jobs::Dto::JobKind::FutureTaskDue => Services::FutureTasks::DeliverDue.new(tasks:, gateway: delivery_gateway) }).tick }.wait
    secret = "test-capability-secret"
    api = Services::FutureTasks::CapabilityApi.new(tasks:, verifier: Adapters::FutureTasks::CapabilityVerifier.new(secret:))
    api.record_disposition(token: capability(secret:, id: "outbox-1"), id: task.id, expected_version: 1, disposition_key: "outbox-answer", outcome: "assessed")

    gateway = OutcomeFailsOnceGateway.new
    worker = Platform::Jobs::Worker.new(handlers: { Platform::Jobs::Dto::JobKind::FutureTaskOutcome => Services::FutureTasks::PublishOutcome.new(gateway:) })
    expect(Async { worker.tick }.wait).to eq(false)
    row = Kirei::App.raw_db_connection[:jobs].where(dispatch_key: "future-task-outcome:#{task.delivery_key}:assessed").first
    expect(row.fetch(:status)).to eq("pending")
    Kirei::App.raw_db_connection[:jobs].where(id: row.fetch(:id)).update(available_at: Time.now - 1)
    expect(Async { worker.tick }.wait).to eq(true)
    expect(gateway.outcomes).to eq([{ delivery_key: task.delivery_key, outcome: "assessed" }])
  end

  it "marks an unknown bridge effect uncertain instead of silently retrying it" do
    task = create_task(due_at: now + 1)
    Kirei::App.raw_db_connection[:jobs].update(available_at: Time.now - 1)
    handler = Services::FutureTasks::DeliverDue.new(tasks:, gateway: Adapters::OpenCode::UnavailableGateway.new)

    Async { Platform::Jobs::Worker.new(handlers: { Platform::Jobs::Dto::JobKind::FutureTaskDue => handler }).tick }.wait

    expect(tasks.find(actor_id: "operator-1", id: task.id).state).to eq(Domains::FutureTasks::Dto::TaskState::Uncertain)
    expect(Kirei::App.raw_db_connection[:future_task_executions].first[:state]).to eq("uncertain")
  end

  it "accepts only one authenticated capability, preserves Commander provenance, and authorizes actor-owned Commander tasks across contexts" do
    secret = "test-capability-secret"
    api = Services::FutureTasks::CapabilityApi.new(tasks:, verifier: Adapters::FutureTasks::CapabilityVerifier.new(secret:))
    token = capability(secret:, id: "cap-1", actor: "operator-1")
    due_at = Time.now + 90
    task = api.create(token:, idempotency_key: "api-create", text: "Check the release", due_at:, timezone: "UTC", local_time: due_at.utc.iso8601)

    expect(task.actor_id).to eq("operator-1")
    expect { api.list(token:) }.to raise_error(ArgumentError, "Capability was already used")
    foreign = capability(secret:, id: "cap-2", actor: "operator-2")
    expect(api.find(token: foreign, id: task.id)).to be_nil
    other_conversation = capability(secret:, id: "cap-3", conversation: "commander:other")
    expect(api.find(token: other_conversation, id: task.id)).to have_attributes(id: task.id)
    expect(task.origin).to eq("commander:main")
    project_task = tasks.create(actor_id: "operator-1", origin: "project:repo", idempotency_key: "project-origin", text: "Open a Commander check-in", due_at: due_at + 60,
                                timezone: "UTC", local_time: (due_at + 60).utc.iso8601)
    cross_context = capability(secret:, id: "cap-4", conversation: "commander:other")
    expect(api.find(token: cross_context, id: project_task.id)).to have_attributes(id: project_task.id)
  end

  it "reconciles an uncertain bridge result with its original delivery key" do
    task = create_task(due_at: now + 1)
    Kirei::App.raw_db_connection[:jobs].update(available_at: Time.now - 1)
    gateway = UncertainThenReconciledGateway.new
    handlers = {
      Platform::Jobs::Dto::JobKind::FutureTaskDue => Services::FutureTasks::DeliverDue.new(tasks:, gateway:),
      Platform::Jobs::Dto::JobKind::FutureTaskReconcile => Services::FutureTasks::ReconcileDue.new(tasks:, gateway:)
    }
    worker = Platform::Jobs::Worker.new(handlers:)
    Async { worker.tick }.wait
    uncertain = tasks.find(actor_id: "operator-1", id: task.id)
    expect(uncertain.state).to eq(Domains::FutureTasks::Dto::TaskState::Uncertain)
    Kirei::App.raw_db_connection[:jobs].where(kind: "future_task.reconcile").update(available_at: Time.now - 1)
    Async { worker.tick }.wait

    settled = tasks.find(actor_id: "operator-1", id: task.id)
    expect(settled.state).to eq(Domains::FutureTasks::Dto::TaskState::AwaitingDisposition)
    expect(settled.delivery_key).to eq(task.delivery_key)
    expect(settled.receipt.commander_item_id).to eq("commander-item-reconciled")
  end

  it "uses the persisted execution sequence for a reconciled redelivery" do
    task = create_task(due_at: now + 1)
    Kirei::App.raw_db_connection[:jobs].update(available_at: Time.now - 1)
    gateway = UncertainThenRedeliveredGateway.new
    handlers = {
      Platform::Jobs::Dto::JobKind::FutureTaskDue => Services::FutureTasks::DeliverDue.new(tasks:, gateway:),
      Platform::Jobs::Dto::JobKind::FutureTaskReconcile => Services::FutureTasks::ReconcileDue.new(tasks:, gateway:)
    }
    worker = Platform::Jobs::Worker.new(handlers:)
    Async { worker.tick }.wait
    Kirei::App.raw_db_connection[:jobs].where(kind: "future_task.reconcile").update(available_at: Time.now - 1)
    Async { worker.tick }.wait

    expect(tasks.find(actor_id: "operator-1", id: task.id).state).to eq(Domains::FutureTasks::Dto::TaskState::AwaitingDisposition)
    expect(gateway.deliveries.map { |delivery| delivery.fetch(:attempt) }).to eq([2])
  end

  it "requires an owner capability to settle an uncertain task as terminally failed" do
    task = create_task(due_at: now + 1)
    Kirei::App.raw_db_connection[:jobs].update(available_at: Time.now - 1)
    handler = Services::FutureTasks::DeliverDue.new(tasks:, gateway: Adapters::OpenCode::UnavailableGateway.new)
    Async { Platform::Jobs::Worker.new(handlers: { Platform::Jobs::Dto::JobKind::FutureTaskDue => handler }).tick }.wait

    secret = "test-capability-secret"
    api = Services::FutureTasks::CapabilityApi.new(tasks:, verifier: Adapters::FutureTasks::CapabilityVerifier.new(secret:))
    non_owner = capability(secret:, id: "cap-non-owner")
    expect { api.resolve_uncertain(token: non_owner, id: task.id, expected_version: 1, resolution_key: "resolve-1", outcome: "failed") }.to raise_error(ArgumentError, "Owner capability is required")
    owner = capability(secret:, id: "cap-owner", owner: true)
    failed = api.resolve_uncertain(token: owner, id: task.id, expected_version: 1, resolution_key: "resolve-1", outcome: "failed", reason: "bridge rejected the key")

    expect(failed.state).to eq(Domains::FutureTasks::Dto::TaskState::Failed)
    retried = api.resolve_uncertain(token: capability(secret:, id: "cap-owner-retry", owner: true), id: task.id, expected_version: 1, resolution_key: "resolve-1", outcome: "failed", reason: "bridge rejected the key")
    expect(retried.state).to eq(Domains::FutureTasks::Dto::TaskState::Failed)
    outcome_job = Platform::Jobs::Store.new.find_by_key(dispatch_key: "future-task-outcome:#{task.delivery_key}:owner_failed")
    expect(outcome_job).not_to be_nil
    expect { tasks.update(actor_id: "operator-1", id: task.id, expected_version: 1, text: "retry", now:) }.to raise_error(ArgumentError, /already started/)
  end

  it "uses the configured normal OpenCode session without exposing its authorization" do
    url, delivery_thread, delivery_request = opencode_response
    gateway = Adapters::OpenCode::ConfiguredGateway.new(base_url: url, session_id: "ses_operator", authorization: "Bearer operator-private-authorization")
    receipt = gateway.deliver(task_id: "task-1", text: "Check", references: [], due_at: now, timezone: "UTC", origin: "commander:main", attempt: 1, delivery_key: "delivery-1")
    delivery_thread.join
    input_id = "msg_future_task_delivery_0b220df1969115139ffebb337981298d243a44f84dad5d20d7e7da5fdb34de43"
    expect(receipt.commander_item_id).to eq(input_id)
    headers, body = delivery_request.pop.split("\r\n\r\n", 2)
    expect(headers).to include("POST /api/session/ses_operator/prompt HTTP/1.1", "Authorization: Bearer operator-private-authorization")
    expect(JSON.parse(body)).to include("id" => input_id, "metadata" => { "fromCommander" => true }, "resume" => true)

    url, reconcile_thread, reconcile_request = opencode_response
    resolution = Adapters::OpenCode::ConfiguredGateway.new(base_url: url, session_id: "ses_operator", authorization: "Bearer operator-private-authorization").reconcile(delivery_key: "delivery-1")
    reconcile_thread.join
    expect(resolution.receipt).to eq(receipt)
    expect(reconcile_request.pop).to include("GET /api/session/ses_operator/message/#{input_id} HTTP/1.1")
  end
end

# frozen_string_literal: true

require "spec_helper"
require "json"
require "openssl"
require "socket"

class RecordingCommanderGateway
  include Adapters::CommanderBridge::Gateway

  attr_reader :deliveries

  def initialize
    @deliveries = []
  end

  def deliver(task_id:, text:, references:, due_at:, timezone:, delivery_key:)
    @deliveries << { task_id:, text:, references:, due_at:, timezone:, delivery_key: }
    Domains::FutureTasks::Dto::DeliveryReceipt.new(delivery_key:, commander_item_id: "commander-item-#{@deliveries.length}")
  end

  def reconcile(delivery_key:)
    Domains::FutureTasks::Dto::BridgeResolution.new(receipt: Domains::FutureTasks::Dto::DeliveryReceipt.new(delivery_key:, commander_item_id: "commander-item-reconciled"))
  end
end

class UncertainThenReconciledGateway < RecordingCommanderGateway
  def initialize
    super
    @first_delivery = true
  end

  def deliver(task_id:, text:, references:, due_at:, timezone:, delivery_key:)
    if @first_delivery
      @first_delivery = false
      raise IOError, "bridge result lost"
    end

    super
  end
end

RSpec.describe Domains::FutureTasks::Tasks do
  let(:tasks) { described_class.new }
  let(:now) { Time.utc(2026, 10, 13, 12, 0, 0) }

  def create_task(key: "create-1", due_at: now + 60)
    tasks.create(actor_id: "operator-1", origin: "commander:main", idempotency_key: key, text: "Review the deployment plan", due_at:, timezone: "UTC",
                 local_time: due_at.utc.iso8601, references: ["repo:digitaltwin"], now:)
  end

  def capability(secret:, id:, actor: "operator-1", conversation: "commander:main", owner: false)
    payload = { "jti" => id, "actor" => actor, "conversation" => conversation, "aud" => "future_tasks", "exp" => (Time.now + 300).to_i, "owner" => owner }.to_json.unpack1("H*")
    "#{payload}.#{OpenSSL::HMAC.hexdigest("SHA256", secret, payload)}"
  end

  def bridge_response(body)
    server = TCPServer.new("127.0.0.1", 0)
    thread = Thread.new do
      client = server.accept
      client.readpartial(4096)
      client.write("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
      client.close
      server.close
    end
    ["http://127.0.0.1:#{server.addr[1]}", thread]
  end

  it "creates one current execution for an actor-scoped idempotency key" do
    first = create_task
    second = create_task

    expect(second).to eq(first)
    expect(Kirei::App.raw_db_connection[:future_tasks].count).to eq(1)
    expect { create_task(due_at: now + 120) }.to raise_error(ArgumentError, /Idempotency key reused/)
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
    expect(Kirei::App.raw_db_connection[:future_task_dispositions].first[:outcome]).to eq("project_work_requested")
  end

  it "marks an unknown bridge effect uncertain instead of silently retrying it" do
    task = create_task(due_at: now + 1)
    Kirei::App.raw_db_connection[:jobs].update(available_at: Time.now - 1)
    handler = Services::FutureTasks::DeliverDue.new(tasks:, gateway: Adapters::CommanderBridge::UnavailableGateway.new)

    Async { Platform::Jobs::Worker.new(handlers: { Platform::Jobs::Dto::JobKind::FutureTaskDue => handler }).tick }.wait

    expect(tasks.find(actor_id: "operator-1", id: task.id).state).to eq(Domains::FutureTasks::Dto::TaskState::Uncertain)
    expect(Kirei::App.raw_db_connection[:future_task_executions].first[:state]).to eq("uncertain")
  end

  it "accepts only one authenticated capability and never trusts a caller-supplied actor" do
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
    expect(api.find(token: other_conversation, id: task.id)).to be_nil
    expect(task.origin).to eq("commander:main")
  end

  it "keeps a daily recurrence at the submitted local wall time across DST" do
    recurrence_now = Time.utc(2027, 3, 1, 0, 0, 0)
    due_at = Time.utc(2027, 3, 13, 14, 30, 0)
    task = tasks.create(actor_id: "operator-1", idempotency_key: "dst", text: "Daily check-in", due_at:, timezone: "America/New_York",
                        local_time: "2027-03-13T09:30:00-05:00", recurrence: "daily", now: recurrence_now)
    Kirei::App.raw_db_connection[:jobs].update(available_at: Time.now - 1)
    gateway = RecordingCommanderGateway.new
    handler = Services::FutureTasks::DeliverDue.new(tasks:, gateway:)
    Async { Platform::Jobs::Worker.new(handlers: { Platform::Jobs::Dto::JobKind::FutureTaskDue => handler }).tick }.wait

    next_task = tasks.record_disposition(actor_id: "operator-1", id: task.id, expected_version: 1, disposition_key: "dst-answer", outcome: "assessed", now: recurrence_now)
    expect(next_task.state).to eq(Domains::FutureTasks::Dto::TaskState::Scheduled)
    expect(next_task.version).to eq(2)
    expect(next_task.local_time).to eq("2027-03-14T09:30:00-04:00")
    expect(next_task.due_at).to eq(Time.utc(2027, 3, 14, 13, 30, 0))
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

  it "requires an owner capability to settle an uncertain task as terminally failed" do
    task = create_task(due_at: now + 1)
    Kirei::App.raw_db_connection[:jobs].update(available_at: Time.now - 1)
    handler = Services::FutureTasks::DeliverDue.new(tasks:, gateway: Adapters::CommanderBridge::UnavailableGateway.new)
    Async { Platform::Jobs::Worker.new(handlers: { Platform::Jobs::Dto::JobKind::FutureTaskDue => handler }).tick }.wait

    secret = "test-capability-secret"
    api = Services::FutureTasks::CapabilityApi.new(tasks:, verifier: Adapters::FutureTasks::CapabilityVerifier.new(secret:))
    non_owner = capability(secret:, id: "cap-non-owner")
    expect { api.resolve_uncertain(token: non_owner, id: task.id, expected_version: 1, resolution_key: "resolve-1", outcome: "failed") }.to raise_error(ArgumentError, "Owner capability is required")
    owner = capability(secret:, id: "cap-owner", owner: true)
    failed = api.resolve_uncertain(token: owner, id: task.id, expected_version: 1, resolution_key: "resolve-1", outcome: "failed", reason: "bridge rejected the key")

    expect(failed.state).to eq(Domains::FutureTasks::Dto::TaskState::Failed)
    expect { tasks.update(actor_id: "operator-1", id: task.id, expected_version: 1, text: "retry", now:) }.to raise_error(ArgumentError, /already started/)
  end

  it "uses the configurable private bridge adapter without exposing an agent credential" do
    url, delivery_thread = bridge_response('{"delivery_key":"delivery-1","commander_item_id":"item-1"}')
    gateway = Adapters::CommanderBridge::ConfiguredGateway.new(base_url: url, identity: "operator-private-identity")
    receipt = gateway.deliver(task_id: "task-1", text: "Check", references: [], due_at: now, timezone: "UTC", delivery_key: "delivery-1")
    delivery_thread.join
    expect(receipt.commander_item_id).to eq("item-1")

    url, reconcile_thread = bridge_response('{"delivery_key":"delivery-1","commander_item_id":"item-1"}')
    resolution = Adapters::CommanderBridge::ConfiguredGateway.new(base_url: url, identity: "operator-private-identity").reconcile(delivery_key: "delivery-1")
    reconcile_thread.join
    expect(resolution.receipt).to eq(receipt)
  end
end

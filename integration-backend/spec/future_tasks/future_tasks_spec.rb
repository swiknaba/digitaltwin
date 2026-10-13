# frozen_string_literal: true

require "spec_helper"

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
end

RSpec.describe Domains::FutureTasks::Tasks do
  let(:tasks) { described_class.new }
  let(:now) { Time.utc(2026, 10, 13, 12, 0, 0) }

  def create_task(key: "create-1", due_at: now + 60)
    tasks.create(actor_id: "operator-1", idempotency_key: key, text: "Review the deployment plan", due_at:, timezone: "UTC",
                 local_time: due_at.utc.iso8601, references: ["repo:digitaltwin"], now:)
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

    completed = tasks.record_disposition(actor_id: "operator-1", id: task.id, expected_version: 1, disposition_key: "answer-1",
                                         outcome: "project_work_requested", now:)
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
end

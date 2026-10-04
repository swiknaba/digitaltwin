# frozen_string_literal: true

require_relative "../../spec_helper"
require_relative "support"

RSpec.describe Domains::Messaging::Outbox do
  include MessagingFixtures

  let(:db) { Kirei::App.raw_db_connection }
  let(:outbox) { described_class.new }

  it "deduplicates an identical message and enqueues one delivery job keyed by outbox id" do
    id = outbox.enqueue(message: outgoing_message).result
    expect(outbox.enqueue(message: outgoing_message).result).to eq(id)
    expect(db[:jobs].select_map(%i[kind dispatch_key])).to eq([["mattermost.post", "outbox:#{id}"]])
    item = outbox.item(id: id)
    expect([item&.status, item&.bot, item&.role, item&.body]).to eq([Domains::Messaging::Dto::OutboxStatus::Pending, Domains::Messaging::Dto::Bot::Worker,
                                                                     Domains::Messaging::Dto::SpeakerRole::Writer, "hello"])
    expect(outbox.item_by_key(key: "response")&.id).to eq(id)
  end

  it "outbox enqueue rejects changed content under same key" do
    outbox.enqueue(message: outgoing_message)
    failure = outbox.enqueue(message: outgoing_message(body: "changed")).errors.first
    expect([failure&.code, failure&.detail]).to eq(["key_reused", "Response key reused with changed content"])
    expect(db[:outbox].count).to eq(1)
    expect(db[:jobs].count).to eq(1)
  end

  it "worker message without thread fails" do
    [outgoing_message(thread_id: nil), outgoing_message(thread_id: ""), outgoing_message(role: Domains::Messaging::Dto::SpeakerRole::Commander)].each do |message|
      failure = outbox.enqueue(message: message).errors.first
      expect([failure&.code, failure&.detail]).to eq(["worker_message_requires_thread_and_role", "Worker messages require thread and role"])
    end
    agent = outgoing_message(thread_id: nil, bot: Domains::Messaging::Dto::Bot::Agent, role: Domains::Messaging::Dto::SpeakerRole::Commander)
    expect(outbox.enqueue(message: agent).success?).to be(true)
    expect(db[:outbox].count).to eq(1)
  end

  it "marks delivery states" do
    id = outbox.enqueue(message: outgoing_message).result
    outbox.mark_uncertain(id: id)
    expect(outbox.mark_delivered(id: id, remote_post_id: "x" * 26, from: Domains::Messaging::Dto::OutboxStatus::Pending)).to be(false)
    expect(outbox.mark_delivered(id: id, remote_post_id: "x" * 26, from: Domains::Messaging::Dto::OutboxStatus::Uncertain)).to be(true)
    expect(db[:outbox][id: id].values_at(:status, :remote_post_id)).to eq(["delivered", "x" * 26])
    outbox.mark_blocked(id: id)
    expect(outbox.item(id: id)&.status).to eq(Domains::Messaging::Dto::OutboxStatus::Blocked)
  end
end

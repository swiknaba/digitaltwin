# frozen_string_literal: true

require_relative "../../spec_helper"
require_relative "support"

RSpec.describe Domains::Messaging::RecordDelivery do
  include MessagingFixtures

  let(:db) { Kirei::App.raw_db_connection }
  let(:service) { described_class.new }

  it "record_delivery dedups by channel/post/kind/revision" do
    first = service.call(delivery: verified_delivery)
    expect(first.result.duplicate).to be(false)
    expect(first.result.inbox_id).to be_a(Integer)

    replay = service.call(delivery: verified_delivery)
    expect(replay.result).to eq(Domains::Messaging::Dto::RecordedDelivery.new(inbox_id: nil, duplicate: true))

    edited = service.call(delivery: verified_delivery(revision: 2, kind: Domains::Messaging::Dto::EventKind::PostEdited))
    other_post = service.call(delivery: verified_delivery(post_id: "q" * 26))
    expect([edited, other_post].map { |result| result.result.duplicate }).to eq([false, false])
    expect(db[:inbox].count).to eq(3)
  end

  it "stores today's verified_delivery JSON keys and reads them back through the inbox" do
    delivery = verified_delivery(root_post: true)
    id = service.call(delivery: delivery).result.inbox_id
    stored = db[:inbox][id: id][:verified_delivery].to_hash
    expect(stored).to eq(
      "channel_id" => "c" * 26, "post_id" => "p" * 26, "thread_id" => "r" * 26,
      "actor" => { "user_id" => "u" * 26, "channel_id" => "c" * 26, "member" => true, "bot" => false },
      "event_kind" => "posted", "post_revision" => 1, "body" => "hello", "root_post" => true
    )
    expect(Domains::Messaging::Inbox.new.find(id: T.must(id))&.verified_delivery).to eq(delivery)
  end
end

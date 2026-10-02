# frozen_string_literal: true

require_relative "../../spec_helper"
require_relative "support"

RSpec.describe Domains::Messaging::Inbox do
  include MessagingFixtures

  let(:db) { Kirei::App.raw_db_connection }
  let(:inbox) { described_class.new }
  # The row shape the pre-refactor router wrote: Sequel.pg_jsonb(VerifiedDelivery#serialize).
  let(:legacy_json) {
    { "channel_id" => "c" * 26, "post_id" => "p" * 26, "thread_id" => "r" * 26,
      "actor" => { "user_id" => "u" * 26, "channel_id" => "c" * 26, "member" => true, "bot" => false },
      "event_kind" => "posted", "post_revision" => 7, "body" => "legacy", "root_post" => false }
  }

  def legacy_row(created_at: Time.now)
    db[:inbox].insert(id: "inbox_#{SecureRandom.hex(6)}", channel_id: "c" * 26, thread_id: "r" * 26, post_id: "p" * 26, post_revision: 7, event_kind: "posted",
                      user_id: "u" * 26, verified_delivery: Sequel.pg_jsonb(legacy_json), created_at: created_at)
  end

  it "round-trips a verified delivery written by the pre-refactor router" do
    record = inbox.find(id: legacy_row)
    expect(record&.verified_delivery).to eq(verified_delivery(body: "legacy", revision: 7))
    expect(record&.verified_delivery&.serialize).to eq(legacy_json)
    expect(inbox.find(id: "inbox_missing")).to be_nil
  end

  it "lists recent records newest first" do
    old = legacy_row(created_at: Time.now - 3600)
    db[:inbox].where(id: old).update(post_id: "o" * 26)
    fresh = legacy_row
    expect(inbox.recent(since: Time.now - 1800, limit: 10).map(&:id)).to eq([fresh])
  end
end

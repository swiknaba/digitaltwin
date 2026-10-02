# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe Domains::Messaging::Checkpoints do
  let(:db) { Kirei::App.raw_db_connection }
  let(:checkpoints) { described_class.new }
  let(:channel) { "c" * 26 }

  it "checkpoint advances only forward" do
    expect(checkpoints.revision(channel_id: channel)).to eq(0)
    checkpoints.advance(channel_id: channel, revision: 3000)
    checkpoints.advance(channel_id: channel, revision: 1500)
    expect(checkpoints.revision(channel_id: channel)).to eq(3000)
    checkpoints.advance(channel_id: channel, revision: 4000)
    expect(checkpoints.revision(channel_id: channel)).to eq(4000)
    expect(db[:chat_checkpoints].count).to eq(1)
  end

  it "quarantines a rejected history post once per digest" do
    2.times { checkpoints.quarantine(channel_id: channel, post_id: nil, digest: "abc", reason: "Malformed history post") }
    rows = db[:audit].where(event_key: "history-rejected:abc").all
    expect(rows.map { |row| [row[:action], row[:channel_id], row[:details].to_hash] }).to eq([["history_rejected", channel, { "reason" => "Malformed history post" }]])
  end
end

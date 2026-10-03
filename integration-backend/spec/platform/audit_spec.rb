# typed: strict
# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe Platform::Audit::Log do
  let(:db) { Kirei::App.raw_db_connection }
  let(:log) { described_class.new }
  let(:details) { Domains::Messaging::Dto::HistoryRejectedAudit.new(reason: "first") }

  it "audit record is unique per event key" do
    log.record(event_key: "event", action: "history_rejected", details: details, channel_id: "c", post_id: "p")
    expect { log.record(event_key: "event", action: "history_rejected", details: details) }.to raise_error(Sequel::UniqueConstraintViolation)
    expect(log.record_once(event_key: "event", action: "other", details: Domains::Messaging::Dto::HistoryRejectedAudit.new(reason: "second"))).to be(false)
    expect(db[:audit].where(event_key: "event").count).to eq(1)
    row = db[:audit].first
    expect(row.values_at(:action, :channel_id, :post_id, :user_id)).to eq(["history_rejected", "c", "p", nil])
    expect(row[:details].to_hash).to eq("reason" => "first")
  end

  it "record_once inserts a new event key and reports it" do
    expect(log.record_once(event_key: "fresh", action: "history_rejected", details: details)).to be(true)
    expect(db[:audit].where(event_key: "fresh").count).to eq(1)
  end

  it "finds a receipt whose details parse strictly into the writer's struct" do
    expect(log.find(event_key: "missing")).to be_nil
    log.record(event_key: "event", action: "history_rejected", details: details)
    receipt = log.find(event_key: "event")
    expect(receipt.action).to eq("history_rejected")
    expect(Domains::Messaging::Dto::HistoryRejectedAudit.from_hash(receipt.details, true)).to eq(details)
    expect { Domains::Messaging::Dto::HistoryRejectedAudit.from_hash(receipt.details.merge("extra" => 1), true) }.to raise_error(RuntimeError)
  end
end

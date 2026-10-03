# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe Domains::Commander::Followups do
  let(:db) { Kirei::App.raw_db_connection }
  let(:followups) { described_class.new }
  let(:interpretation) { Domains::Commander::Dto::RoutingInterpretation.new(workflow_id: "w1", evidence_inbox_ids: ["inbox_2"]) }
  let(:evidence) do
    Domains::Commander::Dto::RoutingEvidence.new(source_inbox_id: "inbox_1", selection: nil, interpretation: interpretation, direct_thread: nil, recent_binding: nil)
  end

  before do
    db[:inbox].insert(id: "inbox_1", channel_id: "c", thread_id: "t", post_id: "p", post_revision: 1, event_kind: "posted", user_id: "u", verified_delivery: Sequel.pg_jsonb({}))
    db[:projects].insert(id: "p1", channel_id: "c", slug: "owner/repo", remote_identity: "github.com/owner/repo", workspace: "/tmp/p1")
    db[:workflows].insert(id: "w1", project_id: "p1", channel_id: "c", thread_id: "root", branch: "b", worktree_path: "/tmp/w1", role_configurations: workflow_roles)
  end

  it "followup creation is idempotent per inbox" do
    first = followups.create(inbox_id: "inbox_1", workflow_id: "w1", session: nil, evidence: evidence)
    second = followups.create(inbox_id: "inbox_1", workflow_id: "w1", session: nil, evidence: evidence)
    expect(second.result).to eq(first.result)
    expect([first.result.status, first.result.reason]).to eq([Domains::Commander::Dto::FollowupStatus::Blocked, "Session reconciliation required"])
    expect(db[:followups].count).to eq(1)
  end

  it "routing_evidence round-trips through the JSONB column with explicit nulls" do
    created = followups.create(inbox_id: "inbox_1", workflow_id: "w1", session: nil, evidence: evidence).result
    expect(db[:followups][id: created.id][:evidence].to_hash).to eq(
      "selection" => nil, "direct_thread" => nil, "interpretation" => { "workflow_id" => "w1", "evidence_inbox_ids" => ["inbox_2"] },
      "recent_binding" => nil, "source_inbox_id" => "inbox_1"
    )
    expect(followups.find(id: created.id)&.evidence).to eq(evidence)
  end

  it "fails closed on a malformed evidence row" do
    created = followups.create(inbox_id: "inbox_1", workflow_id: "w1", session: nil, evidence: evidence).result
    db[:followups].where(id: created.id).update(evidence: Sequel.pg_jsonb("source_inbox_id" => "inbox_1", "unknown" => 1))
    expect { followups.find(id: created.id) }.to raise_error(Domains::Commander::Errors::MalformedRecord)
    db[:followups].where(id: created.id).update(evidence: Sequel.pg_jsonb("source_inbox_id" => 5))
    expect { followups.find(id: created.id) }.to raise_error(Domains::Commander::Errors::MalformedRecord)
  end
end

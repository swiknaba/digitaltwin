require_relative "../../spec_helper"
RSpec.describe "Reviews domain" do
  let(:db) { Kirei::App.raw_db_connection }
  let(:dto) { Domains::Reviews::Dto }
  let(:gate) { Domains::Workflows::Dto::Gate }
  let(:rounds) { Domains::Reviews::Rounds.new }
  let(:verdicts) { Domains::Reviews::Verdicts.new }
  let(:reviewer) { Domains::Workflows::Dto::RoleConfig.from_hash(WorkflowFixtures::WORKFLOW_ROLES.fetch("reviewer")) }
  let(:commit) { "a" * 40 }
  let(:review_commit) { "b" * 40 }

  before do
    db[:projects].insert(id: "project", channel_id: "c", slug: "owner/repo", remote_identity: "github.com/owner/repo", workspace: "/tmp/repo")
    db[:workflows].insert(id: "workflow", project_id: "project", channel_id: "c", thread_id: "root", branch: "b", worktree_path: "/tmp/w", role_configurations: workflow_roles)
  end

  def review(id, round:, gate: "spec", **columns)
    db[:reviews].insert({ id: id, workflow_id: "workflow", gate: gate, round: round, target_commit: commit, review_path: "docs/review.md",
                          reviewer_configuration: session_configuration("reviewer") }.merge(columns))
  end

  def open_round(target_commit: commit, base_commit: nil)
    rounds.open(workflow_id: "workflow", gate: gate::Spec, target_commit: target_commit, base_commit: base_commit, review_path: "docs/review.md", reviewer: reviewer)
  end

  describe "Rounds" do
    it "latest returns highest round" do
      review("review_one", round: 1)
      review("review_three", round: 3)
      review("review_two", round: 2)
      review("review_plan", round: 4, gate: "plan")
      expect(rounds.latest(workflow_id: "workflow", gate: gate::Spec)&.id).to eq("review_three")
      expect(rounds.latest(workflow_id: "workflow", gate: gate::Implementation)).to be_nil
    end

    it "opens numbered rounds with a review id, queued dispatch and the reviewer configuration" do
      first = open_round.result
      expect(first.id).to match(/\Areview_\w{12}\z/)
      expect([first.round, first.gate, first.dispatch_state, first.verdict, first.base_commit]).to eq([1, gate::Spec, dto::DispatchState::Queued, nil, nil])
      expect(open_round(target_commit: "c" * 40, base_commit: "f" * 40).result.round).to eq(2)
      expect(rounds.next_round(workflow_id: "workflow", gate: gate::Spec)).to eq(3)
      expect(rounds.next_round(workflow_id: "workflow", gate: gate::Plan)).to eq(1)
      expect(rounds.find_for_target(workflow_id: "workflow", gate: gate::Spec, target_commit: commit)).to eq(first)
    end

    it "fails RoundsExhausted after three rounds and writes nothing" do
      3.times { |index| review("review_#{index}", round: index + 1, target_commit: (index + 1).to_s * 40) }
      result = open_round(target_commit: "9" * 40)
      expect([result.errors.first.code, result.errors.first.detail]).to eq([dto::ErrorCode::RoundsExhausted.serialize, "Review rounds exhausted"])
      expect(db[:reviews].count).to eq(3)
    end

    it "round-trips reviewer_configuration through JSONB and fails closed on malformed rows" do
      id = open_round.result.id
      expect(db[:reviews][id: id][:reviewer_configuration].to_hash).to eq(reviewer.serialize)
      expect(rounds.find(id: id)&.reviewer_configuration).to eq(reviewer)
      { "missing key" => reviewer.serialize.except("family"), "extra key" => reviewer.serialize.merge("extra" => "x"),
        "wrong type" => reviewer.serialize.merge("launch_args" => "--model") }.each do |label, configuration|
        db[:reviews].where(id: id).update(reviewer_configuration: Sequel.pg_jsonb(configuration))
        expect { rounds.find(id: id) }.to raise_error(Domains::Reviews::Errors::MalformedRecord, "Malformed durable review record"), label
      end
    end

    it "selects the newest changes-requested review, decided reviews and unsettled dispatches" do
      review("review_old", round: 1, verdict: "changes_requested", review_commit: review_commit, created_at: Time.now - 60)
      review("review_new", round: 2, verdict: "changes_requested", review_commit: review_commit, created_at: Time.now)
      review("review_approve", round: 3, verdict: "approve", review_commit: "c" * 40, created_at: Time.now + 60)
      expect(rounds.latest_changes_requested(workflow_id: "workflow")&.id).to eq("review_new")
      expect(rounds.find_decided(workflow_id: "workflow", review_commit: "c" * 40, verdict: dto::Verdict::Approve)&.id).to eq("review_approve")
      expect(rounds.find_decided(workflow_id: "workflow", review_commit: "c" * 40, verdict: dto::Verdict::ChangesRequested)).to be_nil
      expect(rounds.unsettled_dispatch?(workflow_ids: ["workflow"])).to be(false)
      rounds.mark_dispatch(id: "review_old", state: dto::DispatchState::Uncertain)
      expect(rounds.unsettled_dispatch?(workflow_ids: ["workflow"])).to be(true)
      expect(rounds.unsettled_dispatch?(workflow_ids: [])).to be(false)
    end
  end

  describe "Verdicts" do
    it "records the verdict and review commit, and marks the prompt delivered" do
      id = open_round.result.id
      rounds.mark_dispatch(id: id, state: dto::DispatchState::Uncertain)
      recorded = verdicts.record(review_id: id, review_commit: review_commit, verdict: dto::Verdict::ChangesRequested).result
      expect([recorded.verdict, recorded.review_commit, recorded.dispatch_state]).to eq([dto::Verdict::ChangesRequested, review_commit, dto::DispatchState::Delivered])
    end

    it "verdict on already-decided round fails" do
      id = open_round.result.id
      verdicts.record(review_id: id, review_commit: review_commit, verdict: dto::Verdict::Approve)
      result = verdicts.record(review_id: id, review_commit: "c" * 40, verdict: dto::Verdict::ChangesRequested)
      expect([result.errors.first.code, result.errors.first.detail]).to eq([dto::ErrorCode::AlreadyDecided.serialize, "Review already decided"])
      expect(db[:reviews][id: id].values_at(:verdict, :review_commit)).to eq(["approve", review_commit])
      missing = verdicts.record(review_id: "review_missing", review_commit: review_commit, verdict: dto::Verdict::Approve)
      expect(missing.errors.first.code).to eq(dto::ErrorCode::MissingReview.serialize)
    end
  end
end

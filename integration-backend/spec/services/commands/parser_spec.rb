# typed: strict
# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe Services::Commands::Parser do
  dto = Services::Commands::Dto
  uuid = "12345678-1234-4234-8234-123456789abc"
  thread = "t" * 26
  commit = "a" * 40

  def parse(body, agent: "agent", worker: "worker")
    described_class.new.call(body: body, agent_handle: agent, worker_handle: worker)
  end

  it "parses each recovery command with its typed captures" do
    expect(parse("@agent recover-start #{uuid} #{thread}")).to eq(dto::RecoverStart.new(request_id: uuid, thread_id: thread))
    expect(parse("@agent recover-session #{uuid} pane:1.a_b-c")).to eq(dto::RecoverSession.new(operation_id: uuid, pane_id: "pane:1.a_b-c"))
    expect(parse("@agent recover-followup 42 delivered")).to eq(dto::RecoverFollowup.new(followup_id: 42, outcome: dto::FollowupOutcome::Delivered))
    expect(parse("@agent recover-followup 7 discard")).to eq(dto::RecoverFollowup.new(followup_id: 7, outcome: dto::FollowupOutcome::Discard))
    expect(parse("@agent recover-master #{uuid}")).to eq(dto::RecoverMaster.new(request_id: uuid))
  end

  it "parses exact approvals and routed instructions" do
    expect(parse("@agent approve w-1 spec #{commit}")).to eq(dto::Approve.new(workflow_id: "w-1", gate: dto::ApprovalGate::Spec, commit: commit))
    expect(parse("@agent approve w1 plan #{commit}")).to eq(dto::Approve.new(workflow_id: "w1", gate: dto::ApprovalGate::Plan, commit: commit))
    expect(parse("@agent route w1\nPlease cover\nboth cases")).to eq(dto::Route.new(workflow_id: "w1", text: "Please cover\nboth cases"))
  end

  it "parses Worker commands with today's whitespace and word-boundary rules" do
    expect(parse("@worker start")).to eq(dto::WorkerCommand.new(action: dto::WorkerAction::Start, single_space_separator: true))
    expect(parse("@worker  pause now")).to eq(dto::WorkerCommand.new(action: dto::WorkerAction::Pause, single_space_separator: false))
    %w[approve resume finish cancel].each do |action|
      expect(parse("@worker #{action}")).to eq(dto::WorkerCommand.new(action: dto::WorkerAction.deserialize(action), single_space_separator: true))
    end
  end

  it "keeps loose approve/route directives distinct from exact commands" do
    expect(parse("@agent approve w1 spec #{commit.upcase}")).to eq(dto::MalformedDirective.new)
    expect(parse("@agent approve w1 spec #{"a" * 39}")).to eq(dto::MalformedDirective.new)
    expect(parse("@agent route w1")).to eq(dto::MalformedDirective.new)
    expect(parse("@agent approve")).to eq(dto::MalformedDirective.new)
  end

  it "rejects near misses" do
    expect(parse("@agent recover-master #{uuid} ")).to be_nil
    expect(parse("@agent recover-start #{uuid} #{thread} ")).to be_nil
    expect(parse("@agent recover-start #{uuid} #{"T" * 26}")).to be_nil
    expect(parse("@agent recover-followup 4 maybe")).to be_nil
    expect(parse("@other approve w1 spec #{commit}")).to be_nil
    expect(parse("@agent approve w1 spec #{commit}", agent: "other")).to be_nil
    expect(parse("@worker startx")).to be_nil
    expect(parse("hello @worker start")).to be_nil
    expect(parse("@agent please help")).to be_nil
  end

  it "escapes configured handles" do
    expect(parse("@a.b start", worker: "a.b")).to eq(dto::WorkerCommand.new(action: dto::WorkerAction::Start, single_space_separator: true))
    expect(parse("@axb start", worker: "a.b")).to be_nil
  end
end

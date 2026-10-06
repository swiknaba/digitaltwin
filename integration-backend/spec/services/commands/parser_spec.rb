# typed: strict
# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe Services::Commands::Parser do
  dto = Services::Commands::Dto
  uuid = "12345678-1234-4234-8234-123456789abc"
  thread = "t" * 26
  commit = "a" * 40

  def parse(body, commander: "commander", agent: "agent")
    described_class.new.call(body: body, commander_handle: commander, agent_handle: agent)
  end

  it "parses each recovery command with its typed captures" do
    expect(parse("@commander recover-start #{uuid} #{thread}")).to eq(dto::RecoverStart.new(request_id: uuid, thread_id: thread))
    expect(parse("@commander recover-session #{uuid} pane:1.a_b-c")).to eq(dto::RecoverSession.new(operation_id: uuid, pane_id: "pane:1.a_b-c"))
    expect(parse("@commander recover-followup followup_abc123 delivered")).to eq(dto::RecoverFollowup.new(followup_id: "followup_abc123", outcome: dto::FollowupOutcome::Delivered))
    expect(parse("@commander recover-followup followup_def456 discard")).to eq(dto::RecoverFollowup.new(followup_id: "followup_def456", outcome: dto::FollowupOutcome::Discard))
    expect(parse("@commander recover-commander #{uuid}")).to eq(dto::RecoverCommander.new(request_id: uuid))
  end

  it "parses exact approvals and routed instructions" do
    expect(parse("@commander approve w-1 spec #{commit}")).to eq(dto::Approve.new(workflow_id: "w-1", gate: dto::ApprovalGate::Spec, commit: commit))
    expect(parse("@commander approve w1 plan #{commit}")).to eq(dto::Approve.new(workflow_id: "w1", gate: dto::ApprovalGate::Plan, commit: commit))
    expect(parse("@commander route w1\nPlease cover\nboth cases")).to eq(dto::Route.new(workflow_id: "w1", text: "Please cover\nboth cases"))
    expect(parse("@commander route workflow_abcdefghjkmn\nhi")).to eq(dto::Route.new(workflow_id: "workflow_abcdefghjkmn", text: "hi"))
  end

  it "parses project agent commands with today's whitespace and word-boundary rules" do
    expect(parse("@agent start")).to eq(dto::WorkerCommand.new(action: dto::WorkerAction::Start, single_space_separator: true))
    expect(parse("@agent  pause now")).to eq(dto::WorkerCommand.new(action: dto::WorkerAction::Pause, single_space_separator: false))
    %w[approve resume finish cancel].each do |action|
      expect(parse("@agent #{action}")).to eq(dto::WorkerCommand.new(action: dto::WorkerAction.deserialize(action), single_space_separator: true))
    end
  end

  it "keeps loose approve/route directives distinct from exact commands" do
    expect(parse("@commander approve w1 spec #{commit.upcase}")).to eq(dto::MalformedDirective.new)
    expect(parse("@commander approve w1 spec #{"a" * 39}")).to eq(dto::MalformedDirective.new)
    expect(parse("@commander route w1")).to eq(dto::MalformedDirective.new)
    expect(parse("@commander approve")).to eq(dto::MalformedDirective.new)
  end

  it "rejects near misses" do
    expect(parse("@commander recover-commander #{uuid} ")).to be_nil
    expect(parse("@commander recover-start #{uuid} #{thread} ")).to be_nil
    expect(parse("@commander recover-start #{uuid} #{"T" * 26}")).to be_nil
    expect(parse("@commander recover-followup followup_4 maybe")).to be_nil
    expect(parse("@other approve w1 spec #{commit}")).to be_nil
    expect(parse("@commander approve w1 spec #{commit}", commander: "other")).to be_nil
    expect(parse("@agent startx")).to be_nil
    expect(parse("hello @agent start")).to be_nil
    expect(parse("@commander please help")).to be_nil
  end

  it "escapes configured handles" do
    expect(parse("@a.b start", agent: "a.b")).to eq(dto::WorkerCommand.new(action: dto::WorkerAction::Start, single_space_separator: true))
    expect(parse("@axb start", agent: "a.b")).to be_nil
  end
end

# typed: false
# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe Services::JobHandlers do
  kind = Platform::Jobs::Dto::JobKind
  # The kinds of the pre-composition-root Commander::Services#handlers map.
  base_kinds = [
    kind::CommanderPrompt, kind::WorkflowPrompt, kind::SessionFollowup, kind::WorkflowProvision, kind::SessionStart, kind::SessionStop,
    kind::ReviewPrompt, kind::ReviewRelease, kind::ReviewCallback, kind::CommanderControl, kind::SessionRenew, kind::WorkflowPhasePrompt,
    kind::WorkflowStart, kind::WorkflowPause, kind::WorkflowResume, kind::WorkflowFinish, kind::WorkflowCancel, kind::WorkflowApprove
  ].freeze
  commander = { "cli" => "hermes", "provider" => "fixture", "model" => "fixture-hermes", "family" => "fixture", "launch_args" => [] }

  around do |example|
    Dir.mktmpdir("job-handlers") do |dir|
      @dir = dir
      FileUtils.mkdir_p([File.join(dir, "repos"), File.join(dir, "worktrees")])
      example.run
    end
  end

  def handlers(roles)
    bot = Domains::Messaging::Dto::Bot::Agent
    configuration = Services::Configuration.new(
      mattermost_url: "http://mattermost.test", mattermost_listener_token_file: File.join(@dir, "listener-token"), mattermost_local_bot_ids: [],
      mattermost_bot_token_files: { bot => File.join(@dir, "agent-token") }, mattermost_bot_ids: { bot => "b" * 26 }, roles: roles,
      workspace_root: File.join(@dir, "repos"), worktree_root: File.join(@dir, "worktrees")
    )
    described_class.new(composition: Services::Composition.new(configuration: configuration)).call
  end

  it "maps exactly the base kinds to handlers without a commander role", :aggregate_failures do
    map = handlers(nil)

    expect(map.keys).to match_array(base_kinds)
    expect(map.values).to all(be_a(Platform::Jobs::Handler))
  end

  it "adds commander.dispatch when a commander role is configured", :aggregate_failures do
    map = handlers(Domains::Workflows::Records.role_file_from_json(JSON.generate("commander" => commander)))

    expect(map.keys).to match_array(base_kinds + [kind::CommanderDispatch])
    expect(map.values).to all(be_a(Platform::Jobs::Handler))
    expect(map.fetch(kind::CommanderDispatch)).to be_a(Services::Commander::Dispatch)
    expect(map.fetch(kind::CommanderPrompt)).to be_a(Services::Commander::HandleCommanderPrompt)
  end
end

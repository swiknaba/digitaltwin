# typed: false
# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe Services::JobHandlers do
  kind = Platform::Jobs::Dto::JobKind
  # The kinds of the pre-composition-root Commander::Services#handlers map.
  base_kinds = [
    kind::MasterPrompt, kind::WorkflowPrompt, kind::SessionFollowup, kind::WorkflowProvision, kind::SessionStart, kind::SessionStop,
    kind::ReviewPrompt, kind::ReviewRelease, kind::ReviewCallback, kind::MasterControl, kind::SessionRenew, kind::WorkflowPhasePrompt,
    kind::WorkflowStart, kind::WorkflowPause, kind::WorkflowResume, kind::WorkflowFinish, kind::WorkflowCancel, kind::WorkflowApprove
  ].freeze
  controller = { "cli" => "gemini", "provider" => "google", "model" => "fixture-gemini", "family" => "gemini", "launch_args" => [] }

  around do |example|
    Dir.mktmpdir("job-handlers") do |dir|
      @dir = dir
      FileUtils.mkdir_p([File.join(dir, "repos"), File.join(dir, "worktrees")])
      example.run
    end
  end

  def handlers(roles)
    bot = Domains::Messaging::Dto::Bot::Worker
    configuration = Services::Configuration.new(
      mattermost_url: "http://mattermost.test", mattermost_listener_token_file: File.join(@dir, "listener-token"), mattermost_local_bot_ids: [],
      mattermost_bot_token_files: { bot => File.join(@dir, "worker-token") }, mattermost_bot_ids: { bot => "b" * 26 }, roles: roles,
      workspace_root: File.join(@dir, "repos"), worktree_root: File.join(@dir, "worktrees")
    )
    described_class.new(composition: Services::Composition.new(configuration: configuration)).call
  end

  it "maps exactly the base kinds to handlers without a controller role", :aggregate_failures do
    map = handlers(nil)

    expect(map.keys).to match_array(base_kinds)
    expect(map.values).to all(be_a(Platform::Jobs::Handler))
  end

  it "adds master.dispatch when a controller role is configured", :aggregate_failures do
    map = handlers(Domains::Workflows::Records.role_file_from_json(JSON.generate("controller" => controller)))

    expect(map.keys).to match_array(base_kinds + [kind::MasterDispatch])
    expect(map.values).to all(be_a(Platform::Jobs::Handler))
    expect(map.fetch(kind::MasterDispatch)).to be_a(Services::Master::Dispatch)
    expect(map.fetch(kind::MasterPrompt)).to be_a(Services::Master::HandleMasterPrompt)
  end
end

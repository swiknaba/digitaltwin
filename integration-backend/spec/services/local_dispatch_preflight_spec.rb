# typed: strict
# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe Services::LocalDispatchPreflight do
  let(:bot) { Domains::Messaging::Dto::Bot }
  let(:activation) do
    Domains::Workflows::Dto::LocalDispatchActivation.new(
      schema: "digitaltwin.local-dispatch/v1", scope: "local", confirmed_at: "2026-10-05T12:00:00Z", role_config_sha256: "a" * 64
    )
  end
  let(:configuration) do
    Services::Configuration.new(mattermost_url: "http://mattermost.test", mattermost_listener_token_file: "listener.token",
                                mattermost_bot_token_files: { bot::Commander => "commander.token", bot::Agent => "agent.token" },
                                mattermost_bot_ids: { bot::Commander => "commander", bot::Agent => "agent" }, mattermost_channel_ids: ["project"],
                                local_dispatch_activation: activation)
  end
  let(:listener) { instance_double(Adapters::Mattermost::Api) }
  let(:agent) { instance_double(Adapters::Mattermost::Api) }
  let(:commander) { instance_double(Adapters::Mattermost::Api) }
  let(:user) { Adapters::Mattermost::Dto::User.new(id: "listener", delete_at: 0, bot: true) }

  def preflight
    described_class.new(
      configuration: configuration,
      api_factory: ->(_url, token_file) { { "listener.token" => listener, "commander.token" => commander, "agent.token" => agent }.fetch(token_file) },
      panes: -> { [Adapters::Herdr::Dto::PaneSummary.new(pane_id: "pane")] }
    )
  end

  it "requires current authenticated bot identities, memberships, and Herdr before local effects" do
    allow(listener).to receive(:me).and_return(user)
    allow(listener).to receive(:channel).with("project").and_return(Adapters::Mattermost::Dto::Channel.new(id: "project"))
    [[commander, "commander"], [agent, "agent"]].each do |api, id|
      allow(api).to receive(:me).and_return(Adapters::Mattermost::Dto::User.new(id: id, delete_at: 0, bot: true))
      expect(listener).to receive(:member!).with(channel_id: "project", user_id: id).and_return(Adapters::Mattermost::Dto::ChannelMember.new(channel_id: "project", user_id: id))
    end

    expect { preflight.call }.not_to raise_error
  end

  it "fails closed when a configured bot token proves a different account" do
    allow(listener).to receive(:me).and_return(user)
    allow(commander).to receive(:me).and_return(Adapters::Mattermost::Dto::User.new(id: "other", delete_at: 0, bot: true))

    expect { preflight.call }.to raise_error(RuntimeError, "Configured bot identity mismatch")
  end

  it "does not perform remote checks without local activation" do
    inactive = Services::Configuration.new
    expect { described_class.new(configuration: inactive).call }.not_to raise_error
  end
end

# typed: strict
# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe Services::Configuration do
  def with_environment(values)
    previous = values.keys.to_h { |key| [key, ENV[key]] }
    values.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  def role_file
    JSON.generate(WorkflowFixtures::WORKFLOW_ROLES)
  end

  it "keeps dispatch closed without the local activation file" do
    with_environment("LOCAL_DISPATCH_ACTIVATION_FILE" => nil) do
      expect(described_class.from_env.local_dispatch_enabled?).to be(false)
    end
  end

  it "enables only a checked local acknowledgement tied to the role file" do
    Dir.mktmpdir do |dir|
      roles_path = File.join(dir, "roles.json")
      activation_path = File.join(dir, "local-dispatch.json")
      File.write(roles_path, role_file)
      %w[listener agent worker].each { |name| File.write(File.join(dir, "#{name}.token"), "fixture-#{name}") }
      activation = {
        "schema" => "digitaltwin.local-dispatch/v1", "scope" => "local", "confirmed_at" => "2026-10-05T12:00:00Z",
        "role_config_sha256" => Digest::SHA256.file(roles_path).hexdigest
      }
      File.write(activation_path, JSON.generate(activation))
      File.chmod(0o600, activation_path)
      environment = {
        "LOCAL_DISPATCH_ACTIVATION_FILE" => activation_path, "ROLE_CONFIG_FILE" => roles_path,
        "MATTERMOST_URL" => "http://mattermost.test", "MATTERMOST_LISTENER_TOKEN_FILE" => File.join(dir, "listener.token"),
        "MATTERMOST_AGENT_TOKEN_FILE" => File.join(dir, "agent.token"), "MATTERMOST_WORKER_TOKEN_FILE" => File.join(dir, "worker.token"),
        "MATTERMOST_AGENT_BOT_ID" => "agent", "MATTERMOST_WORKER_BOT_ID" => "worker", "MATTERMOST_LOCAL_BOT_IDS" => "agent,worker",
        "MATTERMOST_CHANNEL_IDS" => "project", "COMMANDER_CHANNEL_ID" => nil
      }
      with_environment(environment) do
        configuration = described_class.from_env
        expect([configuration.local_dispatch_enabled?, configuration.chat_transport_enabled?]).to eq([true, true])
        expect(configuration.commander_channel_id).to be_nil
      end
      File.write(roles_path, "{}")
      with_environment(environment) do
        expect { described_class.from_env }.to raise_error(ArgumentError, /role configuration changed/)
      end
    end
  end

  it "requires a monitored channel only when Commander is configured" do
    Dir.mktmpdir do |dir|
      roles_path = File.join(dir, "roles.json")
      activation_path = File.join(dir, "local-dispatch.json")
      File.write(roles_path, JSON.generate(WorkflowFixtures::WORKFLOW_ROLES.merge("commander" => WorkflowFixtures::WORKFLOW_ROLES.fetch("writer").merge("cli" => "hermes"))))
      %w[listener agent worker].each { |name| File.write(File.join(dir, "#{name}.token"), "fixture-#{name}") }
      activation = {
        "schema" => "digitaltwin.local-dispatch/v1",
        "scope" => "local",
        "confirmed_at" => "2026-10-05T12:00:00Z",
        "role_config_sha256" => Digest::SHA256.file(roles_path).hexdigest
      }
      File.write(activation_path, JSON.generate(activation))
      File.chmod(0o600, activation_path)
      environment = {
        "LOCAL_DISPATCH_ACTIVATION_FILE" => activation_path, "ROLE_CONFIG_FILE" => roles_path,
        "MATTERMOST_URL" => "http://mattermost.test", "MATTERMOST_LISTENER_TOKEN_FILE" => File.join(dir, "listener.token"),
        "MATTERMOST_AGENT_TOKEN_FILE" => File.join(dir, "agent.token"), "MATTERMOST_WORKER_TOKEN_FILE" => File.join(dir, "worker.token"),
        "MATTERMOST_AGENT_BOT_ID" => "agent", "MATTERMOST_WORKER_BOT_ID" => "worker", "MATTERMOST_LOCAL_BOT_IDS" => "agent,worker",
        "MATTERMOST_CHANNEL_IDS" => "project", "COMMANDER_CHANNEL_ID" => nil
      }
      with_environment(environment) do
        expect { described_class.from_env }.to raise_error(ArgumentError, /Commander requires a monitored channel/)
      end
    end
  end

  it "rejects an activation acknowledgement that is writable by the group" do
    Dir.mktmpdir do |dir|
      activation_path = File.join(dir, "local-dispatch.json")
      File.write(activation_path, "{}")
      File.chmod(0o660, activation_path)
      with_environment("LOCAL_DISPATCH_ACTIVATION_FILE" => activation_path) do
        expect { described_class.from_env }.to raise_error(ArgumentError, /Invalid local dispatch activation/)
      end
    end
  end
end

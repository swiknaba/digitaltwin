# typed: strict
# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe Adapters::Herdr::Client do
  extend T::Sig

  let(:pending) { { pane_id: "pane", terminal_id: "terminal", name: "fixture", agent_status: "unknown", launch_pending: true } }
  let(:ready) do
    { pane_id: "pane", terminal_id: "terminal", name: "fixture", agent: "pi", agent_status: "idle", interactive_ready: true,
      agent_session: { source: "custom:fixture", agent: "pi", kind: "id", value: "conversation" } }
  end
  let(:launch) { Adapters::Herdr::Dto::LaunchSpec.new(cli: "pi", launch_args: []) }
  let(:workspace_id) { "workspace" }

  sig do
    params(frames: T::Array[T::Hash[Symbol, Object]],
           block: T.proc.params(client: Adapters::Herdr::Client, methods: T::Array[String]).void).void
  end
  def startup_socket(frames:, &block)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "herdr.sock")
      server = UNIXServer.new(path)
      methods = T.let([], T::Array[String])
      thread = Thread.new do
        frames.each_with_index do |frame, _index|
          socket = server.accept
          request = JSON.parse(socket.gets)
          methods << request.fetch("method")
          if frame.key?(:error_code)
            socket.puts(JSON.generate(id: request.fetch("id"), error: { code: frame.fetch(:error_code), message: "fixture detail" }))
          elsif frame.key?(:panes)
            socket.puts(JSON.generate(id: request.fetch("id"), result: { type: "pane_list", panes: frame.fetch(:panes) }))
          elsif frame.key?(:agents)
            socket.puts(JSON.generate(id: request.fetch("id"), result: { type: "agent_list", agents: frame.fetch(:agents) }))
          else
            socket.puts(JSON.generate(id: request.fetch("id"), result: { type: request.fetch("method") == "agent.start" ? "agent_started" : "agent_info", agent: frame }))
          end
          socket.close
        end
      end
      begin
        block.call(described_class.new(socket_path: path), methods)
      ensure
        thread.join(1)
        thread.kill if thread.alive?
        server.close
      end
    end
  end

  it "polls the accepted start until the same terminal proves an interactive conversation" do
    startup_socket(frames: [pending, ready]) do |client, methods|
      live = client.start(pane_id: "pane", name: "fixture", launch: launch)
      expect(live.agent_session&.value).to eq("conversation")
      expect(methods).to eq(["agent.start", "agent.get"])
    end
  end

  it "limits the initial start socket request to the shared startup deadline" do
    stub_const("Adapters::Herdr::Client::STARTUP_TIMEOUT_SECONDS", 1)
    allow(Process).to receive(:clock_gettime).and_return(0.0)
    expect(Timeout).to receive(:timeout).with(1.0).and_call_original
    startup_socket(frames: [ready]) do |client, _methods|
      expect(client.start(pane_id: "pane", name: "fixture", launch: launch).agent_session&.value).to eq("conversation")
    end
  end

  it "retries a redacted get rejection after an accepted start without repeating the start" do
    startup_socket(frames: [pending, { error_code: "upstream_not_ready" }, ready]) do |client, methods|
      live = client.start(pane_id: "pane", name: "fixture", launch: launch)
      expect(live.agent_session&.value).to eq("conversation")
      expect(methods).to eq(["agent.start", "agent.get", "agent.get"])
    end
  end

  it "retries an explicit busy rejection only after the same pane proves untouched" do
    initial_shell = { pane_id: "pane", agent_status: "unknown", workspace_id: workspace_id }
    startup_socket(frames: [initial_shell, { error_code: "agent_pane_busy" }, initial_shell, pending, ready]) do |client, methods|
      expect(client.start(pane_id: "pane", name: "fixture", launch: launch, workspace_id: workspace_id).agent_session&.value).to eq("conversation")
      expect(methods).to eq(["agent.get", "agent.start", "agent.get", "agent.start", "agent.get"])
    end
  end

  it "uses agent list only when a busy pane redacts agent get" do
    initial_shell = { pane_id: "pane", agent_status: "unknown" }
    inventory = initial_shell.merge(workspace_id: workspace_id)
    startup_socket(frames: [inventory, { error_code: "agent_pane_busy" }, { error_code: "not_ready_yet" }, { panes: [inventory] }, { agents: [] }, pending, ready]) do |client, methods|
      expect(client.start(pane_id: "pane", name: "fixture", launch: launch, workspace_id: workspace_id).agent_session&.value).to eq("conversation")
      expect(methods).to eq(["agent.get", "agent.start", "agent.get", "pane.list", "agent.list", "agent.start", "agent.get"])
    end
  end

  it "does not reconcile a busy start without the caller's new workspace identity" do
    startup_socket(frames: [{ error_code: "agent_pane_busy" }]) do |client, methods|
      expect { client.start(pane_id: "pane", name: "fixture", launch: launch) }.to raise_error(Adapters::Herdr::Errors::ProtocolViolation, "Herdr rejected operation: agent_pane_busy")
      expect(methods).to eq(["agent.start"])
    end
  end

  it "does not retry a busy rejection when agent list shows a submitted launch" do
    inventory = { pane_id: "pane", agent_status: "unknown", workspace_id: workspace_id }
    startup_socket(frames: [inventory, { error_code: "agent_pane_busy" }, { error_code: "not_ready_yet" }, { panes: [inventory] }, { agents: [pending.merge(workspace_id: workspace_id)] }]) do |client, methods|
      expect { client.start(pane_id: "pane", name: "fixture", launch: launch, workspace_id: workspace_id) }.to raise_error(Adapters::Herdr::Errors::ProtocolViolation, "Herdr rejected operation: agent_pane_busy")
      expect(methods).to eq(["agent.get", "agent.start", "agent.get", "pane.list", "agent.list"])
    end
  end

  it "does not start when the fresh workspace binding changes before launch" do
    initial_shell = { pane_id: "pane", agent_status: "unknown", workspace_id: "other-workspace" }
    startup_socket(frames: [initial_shell]) do |client, methods|
      expect { client.start(pane_id: "pane", name: "fixture", launch: launch, workspace_id: workspace_id) }.to raise_error(Adapters::Herdr::Errors::ProtocolViolation, "Herdr fresh workspace changed before startup")
      expect(methods).to eq(["agent.get"])
    end
  end

  it "does not retry an explicit busy rejection after a pane has launch state" do
    initial_shell = { pane_id: "pane", agent_status: "unknown", workspace_id: workspace_id }
    startup_socket(frames: [initial_shell, { error_code: "agent_pane_busy" }, ready]) do |client, methods|
      expect { client.start(pane_id: "pane", name: "fixture", launch: launch, workspace_id: workspace_id) }.to raise_error(Adapters::Herdr::Errors::ProtocolViolation, "Herdr rejected operation: agent_pane_busy")
      expect(methods).to eq(["agent.get", "agent.start", "agent.get"])
    end
  end

  it "does not begin a busy-start reconciliation after the shared deadline" do
    stub_const("Adapters::Herdr::Client::STARTUP_TIMEOUT_SECONDS", 0)
    startup_socket(frames: [{ error_code: "agent_pane_busy" }]) do |client, methods|
      expect { client.start(pane_id: "pane", name: "fixture", launch: launch) }.to raise_error(Adapters::Herdr::Errors::ProtocolViolation, "Herdr startup readiness timed out")
      expect(methods).to be_empty
    end
  end

  it "does not inspect or reuse a pane after a redacted start rejection" do
    startup_socket(frames: [{ error_code: "not_ready_yet" }, ready]) do |client, methods|
      expect { client.start(pane_id: "pane", name: "fixture", launch: launch) }.to raise_error(Adapters::Herdr::Errors::ProtocolViolation, "Herdr rejected operation: unknown")
      expect(methods).to eq(["agent.start"])
    end
  end

  it "rejects a replacement terminal without repeating the start" do
    startup_socket(frames: [pending, ready.merge(terminal_id: "replacement")]) do |client, methods|
      expect { client.start(pane_id: "pane", name: "fixture", launch: launch) }.to raise_error(Adapters::Herdr::Errors::ProtocolViolation, "Herdr startup terminal replaced")
      expect(methods).to eq(["agent.start", "agent.get"])
    end
  end

  it "leaves blocked startup unproved and never repeats its effect" do
    startup_socket(frames: [pending, ready.merge(agent_status: "blocked")]) do |client, methods|
      expect { client.start(pane_id: "pane", name: "fixture", launch: launch) }.to raise_error(Adapters::Herdr::Errors::ProtocolViolation, "Herdr startup blocked")
      expect(methods).to eq(["agent.start", "agent.get"])
    end
  end

  it "bounds an unproved startup without another effect" do
    stub_const("Adapters::Herdr::Client::STARTUP_TIMEOUT_SECONDS", 0)
    startup_socket(frames: [pending]) do |client, methods|
      expect { client.start(pane_id: "pane", name: "fixture", launch: launch) }.to raise_error(Adapters::Herdr::Errors::ProtocolViolation, "Herdr startup readiness timed out")
      expect(methods).to be_empty
    end
  end
end

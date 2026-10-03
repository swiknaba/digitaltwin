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
        frames.each_with_index do |frame, index|
          socket = server.accept
          request = JSON.parse(socket.gets)
          methods << request.fetch("method")
          socket.puts(JSON.generate(id: request.fetch("id"), result: { type: index.zero? ? "agent_started" : "agent_info", agent: frame }))
          socket.close
        end
      end
      begin
        block.call(described_class.new(socket_path: path), methods)
      ensure
        thread.join
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
      expect(methods).to eq(["agent.start"])
    end
  end
end

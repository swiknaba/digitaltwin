require_relative "../spec_helper"
RSpec.describe Adapters::Herdr::Client do
  def socket_fixture(type: "agent_info", pane: "pane", wrong_id: false, agent: {}, extra: {})
    Dir.mktmpdir do |dir|
      path = File.join(dir, "herdr.sock")
      server = UNIXServer.new(path)
      requests = []
      thread = Thread.new do
        socket = server.accept
        request = JSON.parse(socket.gets)
        requests << request
        socket.puts(JSON.generate(id: wrong_id ? "wrong" : request["id"], result: {
                                    type: type, agent: { pane_id: pane, agent_status: "idle", **agent }, **extra
                                  }))
        socket.close
      end
      begin
        yield described_class.new(socket_path: path), requests
      ensure
        thread.join
        server.close
      end
    end
  end
  it "uses captured agent.get and agent.prompt wire envelopes on a real local Unix socket" do
    session = { source: "fixture", agent: "codex", kind: "id", value: "conversation" }
    socket_fixture(agent: { name: "writer", cwd: "/w", agent: "codex", agent_session: session, interactive_ready: true, launch_pending: false }) do |client, requests|
      pane = client.pane("pane")
      expect(pane).to eq(Adapters::Herdr::Dto::Pane.new(pane_id: "pane", name: "writer", cwd: "/w", agent: "codex", agent_status: Adapters::Herdr::Dto::AgentStatus::Idle,
                                                        agent_session: Adapters::Herdr::Dto::AgentSession.new(**session), interactive_ready: true, launch_pending: false))
      expect(requests.first.values_at("method", "params")).to eq(["agent.get", { "target" => "pane" }])
    end
    socket_fixture(type: "agent_prompted") do |client, requests|
      client.prompt(pane_id: "pane", text: "follow-up\ntext")
      expect(requests.first.values_at("method", "params")).to eq(["agent.prompt", { "target" => "pane", "text" => "follow-up\ntext" }])
    end
  end
  it "keeps optional schema fields nil and accepts every captured status" do
    %w[idle working blocked done unknown].each do |status|
      socket_fixture(agent: { agent_status: status }) do |client, _|
        pane = client.pane("pane")
        expect([pane.agent_status.serialize, pane.agent_session, pane.name, pane.interactive_ready]).to eq([status, nil, nil, nil])
      end
    end
  end
  it "rejects response correlation, target, result and schema mismatches" do
    violation = Adapters::Herdr::Errors::ProtocolViolation
    expect(violation.ancestors).to include(IOError)
    socket_fixture(wrong_id: true) { |client, _| expect { client.pane("pane") }.to raise_error(violation) }
    socket_fixture(pane: "other") { |client, _| expect { client.pane("pane") }.to raise_error(violation) }
    socket_fixture(type: "ok") { |client, _| expect { client.pane("pane") }.to raise_error(violation) }
    socket_fixture(agent: { agent_status: "sleeping" }) { |client, _| expect { client.pane("pane") }.to raise_error(violation, "Herdr status invalid") }
    socket_fixture(agent: { agent_session: { value: "partial" } }) { |client, _| expect { client.pane("pane") }.to raise_error(violation) }
    socket_fixture(agent: { interactive_ready: "yes" }) { |client, _| expect { client.pane("pane") }.to raise_error(violation) }
  end
  it "maps start, workspace creation and close to captured lifecycle operations on a Unix socket" do
    socket_fixture(type: "agent_started") do |client, requests|
      launch = Adapters::Herdr::Dto::LaunchSpec.new(cli: "codex", launch_args: ["--model", "fixture"])
      expect(client.start(pane_id: "pane", name: "writer", launch: launch).pane_id).to eq("pane")
      expect(requests.first.values_at("method", "params")).to eq(["agent.start", { "pane_id" => "pane", "name" => "writer", "kind" => "codex", "args" => ["--model", "fixture"] }])
    end
    socket_fixture(type: "workspace_created", extra: { workspace: { workspace_id: "ws" }, root_pane: { pane_id: "root" } }) do |client, requests|
      expect(client.create_workspace(cwd: nil, label: "alias", env: { "A" => "b" })).to eq(Adapters::Herdr::Dto::Workspace.new(workspace_id: "ws", root_pane_id: "root"))
      expect(requests.first.values_at("method", "params")).to eq(["workspace.create", { "cwd" => nil, "label" => "alias", "env" => { "A" => "b" }, "focus" => false }])
    end
    socket_fixture(type: "ok") do |client, requests|
      client.close(pane_id: "pane")
      expect(requests.first.values_at("method", "params")).to eq(["pane.close", { "pane_id" => "pane" }])
    end
  end
  it "uses authoritative unfiltered pane inventory for stop receipt recovery" do
    socket_fixture(type: "pane_list", extra: { panes: [{ pane_id: "pane" }] }) do |client, requests|
      expect(client.panes).to eq([Adapters::Herdr::Dto::PaneSummary.new(pane_id: "pane")])
      expect(requests.first.values_at("method", "params")).to eq(["pane.list", {}])
    end
    socket_fixture(type: "pane_list", extra: { panes: [{ other: "unproved" }] }) do |client, _requests|
      expect { client.panes }.to raise_error(IOError)
    end
  end
end

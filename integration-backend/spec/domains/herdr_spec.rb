require_relative "../spec_helper"
RSpec.describe Domains::Sessions::Herdr do
  def socket_fixture(type: "agent_info", pane: "pane", wrong_id: false)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "herdr.sock")
      server = UNIXServer.new(path)
      requests = []
      thread = Thread.new do
        socket = server.accept
        request = JSON.parse(socket.gets)
        requests << request
        socket.puts(JSON.generate(id: wrong_id ? "wrong" : request["id"], result: {
                                    type: type, agent: { pane_id: pane, agent_status: "idle" }
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
    socket_fixture do |client, requests|
      expect(client.get("pane")["pane_id"]).to eq("pane")
      expect(requests.first.values_at("method", "params")).to eq(["agent.get", { "target" => "pane" }])
    end
    socket_fixture(type: "agent_prompted") do |client, requests|
      client.prompt("pane", "follow-up\ntext")
      expect(requests.first.values_at("method", "params")).to eq(["agent.prompt", { "target" => "pane", "text" => "follow-up\ntext" }])
    end
  end
  it "rejects response correlation, target and result mismatches" do
    socket_fixture(wrong_id: true) { |client, _| expect { client.get("pane") }.to raise_error(IOError) }
    socket_fixture(pane: "other") { |client, _| expect { client.get("pane") }.to raise_error(IOError) }
    socket_fixture(type: "ok") { |client, _| expect { client.get("pane") }.to raise_error(IOError) }
  end
  it "maps start and close to captured lifecycle operations on a Unix socket" do
    socket_fixture(type: "agent_started") do |client, requests|
      client.start("pane", "writer", { "cli" => "codex", "launch_args" => ["--model", "fixture"] })
      expect(requests.first.values_at("method", "params")).to eq(["agent.start", { "pane_id" => "pane", "name" => "writer", "kind" => "codex", "args" => ["--model", "fixture"] }])
    end
    socket_fixture(type: "ok") do |client, requests|
      client.close("pane")
      expect(requests.first.values_at("method", "params")).to eq(["pane.close", { "pane_id" => "pane" }])
    end
  end
end

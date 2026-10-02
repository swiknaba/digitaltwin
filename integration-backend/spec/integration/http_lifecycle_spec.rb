require_relative "../spec_helper"
require "socket"
RSpec.describe "Async HTTP ownership and Worker execution (local transport fixture)" do
  def serve_once(status: 200, body: '{"ok":true}')
    server = TCPServer.new("127.0.0.1", 0)
    port = server.addr[1]
    received = Queue.new
    thread = Thread.new do
      socket = server.accept
      header = +""
      header << socket.read(1) until header.end_with?("\r\n\r\n")
      length = header[/Content-Length:\s*(\d+)/i, 1].to_i
      payload = length.positive? ? socket.read(length) : ""
      received << [header, payload]
      socket.write("HTTP/1.1 #{status} Fixture\r\nContent-Type: application/json\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
      socket.close
    ensure
      server.close
    end
    yield port, received
    thread.join
  ensure
    server&.close unless server&.closed?
    thread&.kill if thread&.alive?
  end
  it "makes real async HTTP requests and closes owned clients/responses" do
    Dir.mktmpdir do |dir|
      File.write("#{dir}/token", "disposable-fixture")
      serve_once do |port, received|
        result = Async {
          Adapters::Mattermost::Client.new(url: "http://127.0.0.1:#{port}", token_file: "#{dir}/token").post("/api/v4/posts",
                                                                                                             { "message" => "question" })
        }.wait
        expect(result).to eq("ok" => true)
        header, payload = received.pop
        expect(header).to include("Bearer disposable-fixture")
        expect(JSON.parse(payload)).to eq("message" => "question")
      end
      serve_once(status: 403) do |port, _|
        expect {
          Async {
            Adapters::Mattermost::Client.new(url: "http://127.0.0.1:#{port}",
                                             token_file: "#{dir}/token").get("/api/v4/users/me")
          }.wait
        }.to raise_error(Adapters::Mattermost::Errors::RequestFailed, /403/)
      end
    end
  end
  it "runs the standalone callback executable with standard libraries only" do
    Dir.mktmpdir do |dir|
      File.write("#{dir}/token", "disposable-fixture")
      serve_once(status: 202) do |port, received|
        output, status = Open3.capture2e(
          { "DIGITALTWIN_SESSION_TOKEN_FILE" => "#{dir}/token", "DIGITALTWIN_SESSION_GENERATION" => "1",
            "DIGITALTWIN_CALLBACK_URL" => "http://127.0.0.1:#{port}" }, "ruby", "--disable-gems", "bin/digitaltwin", "say", "--text", "question", "--key", "message"
        )
        expect(status.success?).to be(true)
        expect(output).not_to include("disposable-fixture")
        header, payload = received.pop
        expect(header).to include("POST /internal/callbacks/say")
        expect(JSON.parse(payload)).to eq("generation" => 1, "key" => "message", "text" => "question")
      end
    end
  end
  it "runs the standalone MCP bridge from the adapter sources" do
    Dir.mktmpdir do |dir|
      File.write("#{dir}/token", "disposable-fixture")
      input = JSON.generate(jsonrpc: "2.0", id: 1, method: "initialize") + "\n"
      output, status = Open3.capture2e({ "DIGITALTWIN_CALLBACK_URL" => "http://127.0.0.1:9", "DIGITALTWIN_MASTER_REQUEST_TOKEN_FILE" => "#{dir}/token" },
                                       "ruby", "bin/mcp", stdin_data: input)
      expect(status.success?).to be(true), output
      expect(JSON.parse(output.lines.last).dig("result", "serverInfo", "name")).to eq("digitaltwin")
      expect(output).not_to include("disposable-fixture")
    end
  end
  it "executes injected local handlers outside transactions and fails uncertain effects closed" do
    db = Kirei::App.raw_db_connection
    db[:jobs].delete
    store = Platform::Jobs::Store.new
    kind = Platform::Jobs::Dto::JobKind::MattermostPost
    id = store.enqueue(kind: kind, payload: Domains::Messaging::Dto::OutboxPostJob.new(outbox_id: "effect"), dispatch_key: "effect")
    calls = 0
    handler = Platform::Jobs::CallableHandler.new(lambda do |job|
      expect(db.in_transaction?).to be(false)
      expect(job.lease.begin_effect).to be(true)
      calls += 1
      raise IOError, "Unknown network result"
    end)
    worker = Platform::Jobs::Worker.new(handlers: { kind => handler })
    Async { worker.tick; worker.tick }.wait
    expect(calls).to eq(1)
    expect(db[:jobs][id: id][:status]).to eq("uncertain")
  end
end

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
          Domains::Mattermost::Client.new(url: "http://127.0.0.1:#{port}", token_file: "#{dir}/token").post("/api/v4/posts",
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
            Domains::Mattermost::Client.new(url: "http://127.0.0.1:#{port}",
                                            token_file: "#{dir}/token").get("/api/v4/users/me")
          }.wait
        }.to raise_error(Domains::Mattermost::Client::Error, /403/)
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
  it "executes injected local handlers outside transactions and fails uncertain effects closed" do
    db = Kirei::App.raw_db_connection
    db[:jobs].delete
    store = Domains::Jobs::Store.new
    id = store.enqueue(kind: "fixture", payload: {}, key: "effect")
    calls = 0
    handler = ->(job, jobs) do
      expect(db.in_transaction?).to be(false)
    expect(jobs.begin_effect(id: job.id, lease_token: T.must(job.lease_token))).to be(true)
      calls += 1
      raise IOError, "Unknown network result"
    end
    worker = Domains::Jobs::Worker.new(handlers: { "fixture" => handler })
    Async { worker.tick; worker.tick }.wait
    expect(calls).to eq(1)
    expect(db[:jobs][id: id][:status]).to eq("uncertain")
  end
end

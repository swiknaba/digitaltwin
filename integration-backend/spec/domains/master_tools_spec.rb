require_relative "../spec_helper"
require "stringio"
RSpec.describe "Request-bound Master tools and stdio MCP" do
  let(:db) { Kirei::App.raw_db_connection }
  let(:source) { double(human: true) }
  let(:requests) { Domains::Commander::Requests.new(db, source: source) }
  let(:services) { double(source: source, provision: double(request: "provision-id")) }
  let(:tools) { Domains::Commander::Tools.new(db, services: services, requests: requests) }
  before do
    @inbox = db[:inbox].insert(channel_id: "master", thread_id: "root", post_id: "human-post", post_revision: 1, event_kind: "posted", user_id: "human", verified_delivery: Sequel.pg_jsonb({}))
    db[:sessions].insert(id: "controller", role: "controller", pane_id: "pane", alias: "master", generation: 1, credential_digest: "session-digest", credential_expires_at: Time.now + 3600, configuration: Sequel.pg_jsonb({}))
    db[:master_requests].insert(id: "request", inbox_id: @inbox, session_id: "controller", state: "active", credential_digest: Digest::SHA256.hexdigest("request-token"), expires_at: Time.now + 1800)
  end
  it "requires a live request capability and disallows role/session creation fields" do
    expect(tools.call("list_projects", { "request_id" => "request" }, token: "request-token")).to eq([])
    expect { tools.call("list_projects", { "request_id" => "request" }, token: "worker-token") }.to raise_error(ArgumentError)
    expect { tools.call("start_workflow", { "request_id" => "request", "project_id" => "project", "title" => "task", "role" => "controller" }, token: "request-token") }.to raise_error(ArgumentError)
    db[:master_requests].update(expires_at: Time.now - 1)
    expect { requests.authorize("request", "request-token") }.to raise_error(ArgumentError)
  end
  it "rejects previous Controller generations even with an unexpired request" do
    db[:sessions].insert(id: "replacement", role: "controller", pane_id: "replacement", alias: "replacement", generation: 2, credential_digest: "replacement", credential_expires_at: Time.now + 3600, configuration: Sequel.pg_jsonb({}), active: false)
    expect { requests.authorize("request", "request-token") }.to raise_error(ArgumentError)
  end
  it "queues source and version-bound controls for the socket-owning worker" do
    db[:projects].insert(id: "project", channel_id: "project-channel", slug: "owner/repo", remote_identity: "github.com/owner/repo", workspace: "/tmp/repo")
    db[:workflows].insert(id: "workflow", project_id: "project", channel_id: "project-channel", thread_id: "project-root", branch: "branch", worktree_path: "/tmp/workflow")
    args = { "request_id" => "request", "workflow_id" => "workflow", "action" => "pause", "expected_version" => 0 }
    2.times { expect(tools.call("workflow_control", args, token: "request-token")).to eq({ "status" => "queued" }) }
    expect(db[:jobs].where(kind: "master.control").count).to eq(1)
    expect(db[:workflows].first[:phase]).to eq("spec_writing")
    expect { tools.call("workflow_control", args.merge("expected_version" => 1), token: "request-token") }.to raise_error(ArgumentError)
  end
  it "serves JSON-RPC initialization and request-bound tools without exposing credentials" do
    Dir.mktmpdir do |root|
      token_path = File.join(root, "token")
      File.write(token_path, "request-token")
      input = StringIO.new("invalid\n" + JSON.generate(jsonrpc: "2.0", id: 1, method: "initialize") + "\n" + JSON.generate(jsonrpc: "2.0", id: 2, method: "tools/call", params: { name: "list_projects", arguments: { request_id: "request" } }) + "\n")
      output = StringIO.new
      Adapters::Mcp::Server.new(tools: tools, token_file: token_path).serve(input: input, output: output)
      rows = output.string.lines.map { |line| JSON.parse(line) }
      expect(rows[0].dig("error", "code")).to eq(-32700)
      expect(rows[1].dig("result", "serverInfo", "name")).to eq("digitaltwin")
      expect(rows[2].dig("result", "content", 0, "text")).to eq("[]")
      expect(output.string).not_to include("request-token")
    end
  end
end

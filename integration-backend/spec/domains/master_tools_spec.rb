require_relative "../spec_helper"
require "stringio"

# In-process MCP gateway: raw JSON tool calls through the typed Master tools.
class InProcessTools
  include Adapters::Mcp::Server::ToolGateway

  def initialize(&call) = @call = call
  def definitions = []
  def call(name, args, token:) = @call.call(name, args, token)
end

RSpec.describe "Request-bound Master tools and stdio MCP" do
  let(:db) { Kirei::App.raw_db_connection }
  let(:delivery) {
    Domains::Messaging::Dto::VerifiedDelivery.new(channel_id: "master", thread_id: "root", post_id: "human-post", post_revision: 1, event_kind: Domains::Messaging::Dto::EventKind::Posted,
                                                  root_post: true, body: "@agent help", actor: Domains::Messaging::Dto::VerifiedActor.new(user_id: "human", channel_id: "master", member: true, bot: false))
  }
  let(:source) { double(call: Kirei::Services::Result.new(result: delivery)) }
  let(:authorize) { Services::Master::AuthorizeRequest.new(source: source) }
  let(:service) do
    Services::Master::Tools.new(source: source, authorize: authorize, request_start: double(call: Kirei::Services::Result.new(result: "provision-id")), route: double)
  end
  let(:tools) { InProcessTools.new { |name, args, token| call_tool(name, args, token: token) } }

  def arguments(values)
    evidence = values["evidence_inbox_ids"]
    Services::Master::Dto::ToolArguments.new(
      fields: values.keys, request_id: values["request_id"], project_id: values["project_id"], title: values["title"], workflow_id: values["workflow_id"],
      action: values["action"], expected_version: values["expected_version"].is_a?(Integer) ? values["expected_version"] : nil,
      evidence_inbox_ids: evidence.is_a?(Array) ? evidence.map { |item| item.is_a?(String) ? item : nil } : nil
    )
  end

  # Raises the failure detail, as the pre-refactor tools did.
  def call_tool(name, values, token:)
    result = service.call(name: Services::Master::Dto::ToolName.deserialize(name), arguments: arguments(values), token: token)
    raise ArgumentError, result.errors.first.detail if result.failed?

    Adapters::Http::ToolJson.call(result.result)
  end

  def authorize_request(id, token)
    result = authorize.call(id: id, token: token, states: [Domains::Commander::Dto::MasterRequestState::Active])
    raise ArgumentError, result.errors.first.detail if result.failed?
  end
  before do
    @inbox = db[:inbox].insert(id: "inbox_1", channel_id: "master", thread_id: "root", post_id: "human-post", post_revision: 1, event_kind: "posted", user_id: "human", verified_delivery: Sequel.pg_jsonb({}))
    db[:sessions].insert(id: "controller", role: "controller", pane_id: "pane", alias: "master", generation: 1, credential_digest: "session-digest", credential_expires_at: Time.now + 3600, configuration: session_configuration("controller"))
    db[:master_requests].insert(id: "request", inbox_id: @inbox, session_id: "controller", state: "active", credential_digest: Digest::SHA256.hexdigest("request-token"), expires_at: Time.now + 1800)
  end
  it "requires a live request capability and disallows role/session creation fields" do
    expect(call_tool("list_projects", { "request_id" => "request" }, token: "request-token")).to eq([])
    expect { call_tool("list_projects", { "request_id" => "request" }, token: "worker-token") }.to raise_error(ArgumentError)
    expect { call_tool("start_workflow", { "request_id" => "request", "project_id" => "project", "title" => "task", "role" => "controller" }, token: "request-token") }.to raise_error(ArgumentError)
    db[:master_requests].update(expires_at: Time.now - 1)
    expect { authorize_request("request", "request-token") }.to raise_error(ArgumentError)
  end
  it "rejects previous Controller generations even with an unexpired request" do
    db[:sessions].insert(id: "replacement", role: "controller", pane_id: "replacement", alias: "replacement", generation: 2, credential_digest: "replacement", credential_expires_at: Time.now + 3600, configuration: session_configuration("controller"), active: false)
    expect { authorize_request("request", "request-token") }.to raise_error(ArgumentError)
  end
  it "queues source and version-bound controls for the socket-owning worker" do
    db[:projects].insert(id: "project", channel_id: "project-channel", slug: "owner/repo", remote_identity: "github.com/owner/repo", workspace: "/tmp/repo")
    db[:workflows].insert(id: "workflow", project_id: "project", channel_id: "project-channel", thread_id: "project-root", branch: "branch", worktree_path: "/tmp/workflow", role_configurations: workflow_roles)
    args = { "request_id" => "request", "workflow_id" => "workflow", "action" => "pause", "expected_version" => 0 }
    2.times { expect(call_tool("workflow_control", args, token: "request-token")).to eq({ "status" => "queued" }) }
    expect(db[:jobs].where(kind: "master.control").count).to eq(1)
    expect(db[:workflows].first[:phase]).to eq("spec_writing")
    expect { call_tool("workflow_control", args.merge("expected_version" => 1), token: "request-token") }.to raise_error(ArgumentError)
  end
  it "rejects unexpected and mistyped fields as a failure result before the capability check" do
    unexpected = service.call(name: Services::Master::Dto::ToolName::ListProjects, arguments: arguments("request_id" => "request", "role" => "controller"), token: "worker-token")
    expect(unexpected.errors.map { |error| [error.code, error.detail] }).to eq([%w[unexpected_fields Unexpected\ tool\ fields]])
    args = { "request_id" => "request", "workflow_id" => "workflow", "action" => "pause", "expected_version" => "0" }
    mistyped = service.call(name: Services::Master::Dto::ToolName::WorkflowControl, arguments: arguments(args), token: "worker-token")
    expect(mistyped.errors.map(&:detail)).to eq(["Invalid tool arguments"])
    expect(db[:jobs].count).to eq(0)
  end
  it "skips a corrupt inbox row in read_context instead of failing the call" do
    db[:inbox].insert(id: "inbox_2", channel_id: "master", thread_id: "root", post_id: "other-post", post_revision: 1, event_kind: "posted", user_id: "human",
                      verified_delivery: Sequel.pg_jsonb({ "channel_id" => "master" }))
    db[:inbox].where(id: @inbox).update(verified_delivery: Sequel.pg_jsonb(delivery.serialize))
    expect(call_tool("read_context", { "request_id" => "request" }, token: "request-token")).to eq(
      [{ "inbox_id" => @inbox, "channel_id" => "master", "thread_id" => "root", "text" => "@agent help" }]
    )
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

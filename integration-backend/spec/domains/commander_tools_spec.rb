require_relative "../spec_helper"
require "stringio"

# In-process MCP gateway: raw JSON tool calls through the typed Commander tools.
class InProcessTools
  include Adapters::Mcp::Server::ToolGateway

  def initialize(&call) = @call = call
  def definitions = []
  def call(name, args, token:) = @call.call(name, args, token)
end

RSpec.describe "Request-bound Commander tools and stdio MCP" do
  let(:db) { Kirei::App.raw_db_connection }
  let(:delivery) {
    Domains::Messaging::Dto::VerifiedDelivery.new(channel_id: "commander", thread_id: "root", post_id: "human-post", post_revision: 1, event_kind: Domains::Messaging::Dto::EventKind::Posted,
                                                  root_post: true, body: "@agent help", actor: Domains::Messaging::Dto::VerifiedActor.new(user_id: "human", channel_id: "commander", member: true, bot: false))
  }
  let(:source) { double(call: Kirei::Services::Result.new(result: delivery)) }
  let(:authorize) { Services::Commander::AuthorizeRequest.new(source: source) }
  let(:service) do
    Services::Commander::Tools.new(source: source, authorize: authorize, request_start: double(call: Kirei::Services::Result.new(result: "provision-id")), route: double)
  end
  let(:tools) { InProcessTools.new { |name, args, token| call_tool(name, args, token: token) } }

  def arguments(values)
    evidence = values["evidence_inbox_ids"]
    Services::Commander::Dto::ToolArguments.new(
      fields: values.keys, request_id: values["request_id"], project_id: values["project_id"], title: values["title"], workflow_id: values["workflow_id"],
      action: values["action"], expected_version: values["expected_version"].is_a?(Integer) ? values["expected_version"] : nil,
      evidence_inbox_ids: evidence.is_a?(Array) ? evidence.map { |item| item.is_a?(String) ? item : nil } : nil
    )
  end

  # Raises the failure detail, as the pre-refactor tools did.
  def call_tool(name, values, token:)
    result = service.call(name: Services::Commander::Dto::ToolName.deserialize(name), arguments: arguments(values), token: token)
    raise ArgumentError, result.errors.first.detail if result.failed?

    Adapters::Http::ToolJson.call(result.result)
  end

  def authorize_request(id, token)
    result = authorize.call(id: id, token: token, states: [Domains::Commander::Dto::CommanderRequestState::Active])
    raise ArgumentError, result.errors.first.detail if result.failed?
  end
  before do
    @inbox = db[:inbox].insert(id: "inbox_1", channel_id: "commander", thread_id: "root", post_id: "human-post", post_revision: 1, event_kind: "posted", user_id: "human", verified_delivery: Sequel.pg_jsonb({}))
    db[:sessions].insert(id: "commander", role: "commander", pane_id: "pane", alias: "commander", generation: 1, credential_digest: "session-digest", credential_expires_at: Time.now + 3600, configuration: session_configuration("commander"))
    db[:commander_requests].insert(id: "request", inbox_id: @inbox, session_id: "commander", state: "active", credential_digest: Digest::SHA256.hexdigest("request-token"), expires_at: Time.now + 1800)
  end
  it "requires a live request capability and disallows role/session creation fields" do
    expect(call_tool("list_projects", { "request_id" => "request" }, token: "request-token")).to eq([])
    expect { call_tool("list_projects", { "request_id" => "request" }, token: "worker-token") }.to raise_error(ArgumentError)
    expect { call_tool("start_workflow", { "request_id" => "request", "project_id" => "project", "title" => "task", "role" => "commander" }, token: "request-token") }.to raise_error(ArgumentError)
    db[:commander_requests].update(expires_at: Time.now - 1)
    expect { authorize_request("request", "request-token") }.to raise_error(ArgumentError)
  end
  it "rejects previous Commander generations even with an unexpired request" do
    db[:sessions].insert(id: "replacement", role: "commander", pane_id: "replacement", alias: "replacement", generation: 2, credential_digest: "replacement", credential_expires_at: Time.now + 3600, configuration: session_configuration("commander"), active: false)
    expect { authorize_request("request", "request-token") }.to raise_error(ArgumentError)
  end
  it "queues source and version-bound controls for the socket-owning worker" do
    db[:projects].insert(id: "project", channel_id: "project-channel", slug: "owner/repo", remote_identity: "github.com/owner/repo", workspace: "/tmp/repo")
    db[:workflows].insert(id: "workflow", project_id: "project", channel_id: "project-channel", thread_id: "project-root", branch: "branch", worktree_path: "/tmp/workflow", role_configurations: workflow_roles)
    args = { "request_id" => "request", "workflow_id" => "workflow", "action" => "pause", "expected_version" => 0 }
    2.times { expect(call_tool("workflow_control", args, token: "request-token")).to eq({ "status" => "queued" }) }
    expect(db[:jobs].where(kind: "commander.control").count).to eq(1)
    expect(db[:workflows].first[:phase]).to eq("spec_writing")
    expect { call_tool("workflow_control", args.merge("expected_version" => 1), token: "request-token") }.to raise_error(ArgumentError)
  end

  it "reports only visible workflow status from durable records" do
    db[:projects].insert(id: "project", channel_id: "project-channel", slug: "owner/repo", remote_identity: "github.com/owner/repo", workspace: "/tmp/repo")
    db[:workflows].insert(id: "workflow", project_id: "project", channel_id: "project-channel", thread_id: "project-root", branch: "branch", worktree_path: "/tmp/workflow", blocker: "Waiting for human approval", role_configurations: workflow_roles)
    db[:sessions].insert(
      id: "writer", workflow_id: "workflow", role: "writer", pane_id: "pane", alias: "writer", generation: 1,
      credential_digest: "writer-digest", credential_expires_at: Time.now + 3600, configuration: session_configuration,
      state: "working", last_verified_at: Time.utc(2026, 10, 4, 12, 0, 0)
    )
    db[:workflows].insert(id: "hidden", project_id: "project", channel_id: "hidden-channel", thread_id: "hidden-root", branch: "hidden", worktree_path: "/tmp/hidden", role_configurations: workflow_roles)

    visible = Domains::Messaging::Dto::VerifiedDelivery.new(
      channel_id: "project-channel", thread_id: "project-root", post_id: "status-post", post_revision: 1,
      event_kind: Domains::Messaging::Dto::EventKind::Posted, root_post: true, body: "@agent status",
      actor: Domains::Messaging::Dto::VerifiedActor.new(user_id: "human", channel_id: "project-channel", member: true, bot: false)
    )
    allow(source).to receive(:call) do |inbox_id: _inbox_id, destination: nil|
      destination == "hidden-channel" ? Kirei::Services::Result.new(errors: Platform::Failure.call(code: Domains::Messaging::Dto::ErrorCode::DestinationMembershipRequired, detail: "Hidden")) :
        Kirei::Services::Result.new(result: visible)
    end

    expect(call_tool("workflow_status", { "request_id" => "request" }, token: "request-token")).to eq(
      [{ "project_id" => "project", "project_slug" => "owner/repo", "workflow_id" => "workflow", "thread_id" => "project-root", "phase" => "spec_writing",
         "wait_reason" => "Waiting for human approval", "session_state" => "working", "last_verified_at" => Time.utc(2026, 10, 4, 12, 0, 0), "review_state" => nil,
         "approval_state" => nil, "delivery_state" => nil, "artifact_links" => [] }]
    )
  end
  it "rejects unexpected and mistyped fields as a failure result before the capability check" do
    unexpected = service.call(name: Services::Commander::Dto::ToolName::ListProjects, arguments: arguments("request_id" => "request", "role" => "commander"), token: "worker-token")
    expect(unexpected.errors.map { |error| [error.code, error.detail] }).to eq([%w[unexpected_fields Unexpected\ tool\ fields]])
    args = { "request_id" => "request", "workflow_id" => "workflow", "action" => "pause", "expected_version" => "0" }
    mistyped = service.call(name: Services::Commander::Dto::ToolName::WorkflowControl, arguments: arguments(args), token: "worker-token")
    expect(mistyped.errors.map(&:detail)).to eq(["Invalid tool arguments"])
    expect(db[:jobs].count).to eq(0)
  end
  it "skips a corrupt inbox row in read_context instead of failing the call" do
    db[:inbox].insert(id: "inbox_2", channel_id: "commander", thread_id: "root", post_id: "other-post", post_revision: 1, event_kind: "posted", user_id: "human",
                      verified_delivery: Sequel.pg_jsonb({ "channel_id" => "commander" }))
    db[:inbox].where(id: @inbox).update(verified_delivery: Sequel.pg_jsonb(delivery.serialize))
    expect(call_tool("read_context", { "request_id" => "request" }, token: "request-token")).to eq(
      [{ "inbox_id" => @inbox, "channel_id" => "commander", "thread_id" => "root", "text" => "@agent help" }]
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

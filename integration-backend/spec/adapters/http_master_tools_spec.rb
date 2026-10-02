# frozen_string_literal: true

require_relative "../spec_helper"
require "rack/mock"

# Pins the exact JSON body of every request-bound Master tool. The expected
# strings were captured from the pre-refactor Domains::Commander::Tools.
RSpec.describe "POST /internal/master/tools wire format" do
  let(:db) { Kirei::App.raw_db_connection }
  let(:app) { Digitaltwin.new }
  let(:user) { "u" * 26 }
  let(:workflow_channel) { "c" * 26 }
  let(:deliveries) { {} }
  let(:resolver) { double }
  let(:membership) { double(member?: true) }

  # Verifies only stored deliveries; hidden and raising channels fail.
  let(:source) do
    known = deliveries
    double.tap do |verifier|
      allow(verifier).to receive(:call) do |inbox_id:, destination: nil|
        raise Adapters::Mattermost::Errors::RequestFailed.new("Mattermost HTTP 500", status: 500) if destination == "raising-channel"
        next Kirei::Services::Result.new(errors: [Kirei::Errors::JsonApiError.new(code: "x", detail: "Destination membership required")]) if destination == "hidden-channel"

        Kirei::Services::Result.new(result: known.fetch(inbox_id))
      end
    end
  end

  def delivery(id, channel_id:, thread_id:, body:, revision: 1)
    value = Domains::Messaging::Dto::VerifiedDelivery.new(channel_id: channel_id, thread_id: thread_id, post_id: "post-#{id}", post_revision: revision,
                                                          event_kind: Domains::Messaging::Dto::EventKind::Posted, root_post: false, body: body,
                                                          actor: Domains::Messaging::Dto::VerifiedActor.new(channel_id: channel_id, user_id: user, member: true, bot: false))
    db[:inbox].insert(id: id, channel_id: channel_id, thread_id: thread_id, post_id: value.post_id, post_revision: revision, event_kind: "posted", user_id: user,
                      verified_delivery: Sequel.pg_jsonb(value.serialize), created_at: Time.now - deliveries.size)
    allow(resolver).to receive(:delivery).with(post_id: value.post_id, channel_id: channel_id, event_kind: Domains::Messaging::Dto::EventKind::Posted).and_return(value)
    deliveries[id] = value
  end

  before do
    delivery("inbox_1", channel_id: "master", thread_id: "root", body: "@agent help")
    delivery("inbox_2", channel_id: workflow_channel, thread_id: "root1", body: "We should cover retries")
    db[:sessions].insert(id: "controller", role: "controller", pane_id: "pane", alias: "master", generation: 1, credential_digest: "session-digest",
                         credential_expires_at: Time.now + 3600, configuration: session_configuration("controller"))
    db[:master_requests].insert(id: "request", inbox_id: "inbox_1", session_id: "controller", state: "active",
                                credential_digest: Digest::SHA256.hexdigest("request-token"), expires_at: Time.now + 1800)
    db[:projects].insert(id: "p1", channel_id: workflow_channel, slug: "owner/repo", remote_identity: "github.com/owner/repo", workspace: "/tmp/p1")
    db[:projects].insert(id: "p2", channel_id: "hidden-channel", slug: "owner/hidden", remote_identity: "github.com/owner/hidden", workspace: "/tmp/p2")
    db[:projects].insert(id: "p3", channel_id: "raising-channel", slug: "owner/raising", remote_identity: "github.com/owner/raising", workspace: "/tmp/p3")
    db[:workflows].insert(id: "w1", project_id: "p1", channel_id: workflow_channel, thread_id: "root1", branch: "b1", worktree_path: "/tmp/w1", phase: "implementation",
                          version: 2, artifacts: Sequel.pg_jsonb("spec" => { "commit" => "a" * 40, "path" => "docs/spec.md" }), source_inbox_id: "inbox_2",
                          role_configurations: workflow_roles)
    db[:workflows].insert(id: "w2", project_id: "p2", channel_id: "hidden-channel", thread_id: "root2", branch: "b2", worktree_path: "/tmp/w2", role_configurations: workflow_roles)
    db[:sessions].insert(id: "s1", workflow_id: "w1", role: "writer", generation: 1, pane_id: "pane1", alias: "writer1", credential_digest: "digest1",
                         credential_expires_at: Time.now + 3600, configuration: session_configuration)
    stub_master_tools
  end

  def stub_master_tools
    route = Services::Master::RouteFollowup.new(resolver: resolver, membership: membership, handle: "agent", master_channel_id: nil)
    tools = Services::Master::Tools.new(source: source, authorize: Services::Master::AuthorizeRequest.new(source: source), route: route,
                                        request_start: double(call: Kirei::Services::Result.new(result: "workflow_request_1")))
    allow(Services::Composition).to receive(:instance).and_return(double(tools: tools))
  end

  def tool(name, arguments = {}, token = "request-token")
    body = JSON.generate("name" => name, "arguments" => arguments.merge("request_id" => "request"))
    env = Rack::MockRequest.env_for("http://localhost/internal/master/tools", method: "POST", input: body, "CONTENT_TYPE" => "application/json")
    env.merge!("REQUEST_PATH" => "/internal/master/tools", "HTTP_HOST" => "localhost", "REMOTE_ADDR" => "127.0.0.1", "HTTP_AUTHORIZATION" => "Bearer #{token}")
    status, _headers, chunks = app.call(env)
    [status, chunks.join]
  end

  it "keeps the manifest body" do
    env = Rack::MockRequest.env_for("http://localhost/internal/master/manifest", method: "GET")
    env.merge!("REQUEST_PATH" => "/internal/master/manifest", "HTTP_HOST" => "localhost", "REMOTE_ADDR" => "127.0.0.1")
    status, _headers, chunks = app.call(env)
    # SHA-256 of the pre-refactor manifest. Evidence items keep the manifest's "integer" type.
    expect([status, Digest::SHA256.hexdigest(chunks.join)]).to eq([200, "c8018620f83ad4f7d6320930f471f7def23e8ec3b5500d78190cad7b23f04a60"])
    expect(chunks.join).to include('"evidence_inbox_ids":{"type":"array","items":{"type":"integer"},"maxItems":10}')
  end

  it "keeps the list_projects body" do
    expect(tool("list_projects")).to eq([200, '{"result":[{"id":"p1","slug":"owner/repo","channel_id":"cccccccccccccccccccccccccc"}]}'])
  end

  it "keeps the list_workflows body" do
    expect(tool("list_workflows")).to eq([200, '{"result":[{"id":"w1","project_id":"p1","channel_id":"cccccccccccccccccccccccccc","thread_id":"root1",' \
                                               '"phase":"implementation","version":2,"artifacts":{"spec":{"path":"docs/spec.md","commit":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}},' \
                                               '"source_inbox_id":"inbox_2"}]}'])
  end

  it "keeps the read_context body" do
    expect(tool("read_context")).to eq([200, '{"result":[{"inbox_id":"inbox_1","channel_id":"master","thread_id":"root","text":"@agent help"},' \
                                             '{"inbox_id":"inbox_2","channel_id":"cccccccccccccccccccccccccc","thread_id":"root1","text":"We should cover retries"}]}'])
  end

  it "keeps the start_workflow body" do
    expect(tool("start_workflow", "project_id" => "p1", "title" => "task")).to eq([200, '{"result":{"request_id":"workflow_request_1"}}'])
  end

  it "keeps the send_prompt body for a queued follow-up and for a clarification" do
    status, body = tool("send_prompt", "workflow_id" => "w1", "evidence_inbox_ids" => ["inbox_2"])
    row = db[:followups].first
    expect([status, body]).to eq([200, "{\"result\":{\"id\":\"#{row[:id]}\",\"inbox_id\":\"inbox_1\",\"workflow_id\":\"w1\",\"session_id\":\"s1\",\"generation\":1," \
                                       "\"status\":\"queued\",\"reason\":null,\"evidence\":{\"selection\":null,\"direct_thread\":null," \
                                       "\"interpretation\":{\"workflow_id\":\"w1\",\"evidence_inbox_ids\":[\"inbox_2\"]},\"recent_binding\":null," \
                                       "\"source_inbox_id\":\"inbox_1\"},\"created_at\":\"#{row[:created_at]}\",\"delivered_at\":null}}"])
    expect(tool("send_prompt", "workflow_id" => "w1", "evidence_inbox_ids" => ["inbox_2"])).to eq([status, body])
    # A request from w2's thread: direct w2 plus interpreted w1 needs clarification.
    delivery("inbox_3", channel_id: "hidden-channel", thread_id: "root2", body: "Which one?")
    db[:master_requests].where(id: "request").update(inbox_id: "inbox_3")
    expect(tool("send_prompt", "workflow_id" => "w1", "evidence_inbox_ids" => ["inbox_2"])).to eq([200, '{"result":{"status":"clarification"}}'])
  end

  it "keeps the workflow_control body" do
    expect(tool("workflow_control", "workflow_id" => "w1", "action" => "pause", "expected_version" => 2)).to eq([200, '{"result":{"status":"queued"}}'])
  end

  it "keeps the rejected and unexpected-field bodies" do
    expect(tool("list_projects", "role" => "controller")).to eq([403, '{"error":"Request rejected"}'])
    expect(tool("list_projects", {}, "worker-token")).to eq([403, '{"error":"Request rejected"}'])
    expect(tool("workflow_control", "workflow_id" => "w1", "action" => "pause", "expected_version" => "2")).to eq([403, '{"error":"Request rejected"}'])
  end
end

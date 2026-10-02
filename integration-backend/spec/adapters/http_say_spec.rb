# frozen_string_literal: true

require_relative "../spec_helper"
require "rack/mock"

RSpec.describe "POST /internal/callbacks/say wire format" do
  let(:db) { Kirei::App.raw_db_connection }
  let(:app) { Digitaltwin.new }

  before do
    db[:projects].insert(id: "p", channel_id: "c", slug: "owner/repo", remote_identity: "github.com/owner/repo", workspace: "/workspace/repos/owner/repo")
    db[:workflows].insert(id: "w", project_id: "p", channel_id: "c", thread_id: "root", branch: "digitaltwin/fixture", worktree_path: "/workspace/worktrees/fixture", role_configurations: workflow_roles)
    db[:sessions].insert(id: "s", workflow_id: "w", role: "writer", generation: 1, pane_id: "pane", alias: "alias",
                         configuration: Sequel.pg_jsonb({}), credential_digest: Digest::SHA256.hexdigest("fixture-token"), credential_expires_at: Time.now + 60)
  end

  def say(text, token: "fixture-token")
    body = JSON.generate("generation" => 1, "key" => "message", "text" => text)
    env = Rack::MockRequest.env_for("http://localhost/internal/callbacks/say", method: "POST", input: body, "CONTENT_TYPE" => "application/json")
    env.merge!("REQUEST_PATH" => "/internal/callbacks/say", "HTTP_HOST" => "localhost", "REMOTE_ADDR" => "127.0.0.1", "HTTP_AUTHORIZATION" => "Bearer #{token}")
    status, _headers, chunks = app.call(env)
    [status, chunks.join]
  end

  it "keeps the accepted and rejected bodies and status codes" do
    expect(say("question")).to eq([202, '{"status":"accepted","reason":"Queued in bound thread"}'])
    expect(say("changed")).to eq([403, '{"status":"rejected","reason":"Callback key reused with changed body"}'])
    expect(say("question", token: "wrong")).to eq([403, '{"status":"rejected","reason":"Invalid or stale session"}'])
  end
end

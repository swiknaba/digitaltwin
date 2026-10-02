require_relative "../spec_helper"
RSpec.describe "Source-derived Mattermost delivery verification contracts (offline)" do
  let(:db) { Kirei::App.raw_db_connection }
  let(:channel) { "c" * 26 }
  let(:user_id) { "h" * 26 }
  let(:root_id) { "r" * 26 }
  let(:post_id) { "p" * 26 }
  let(:root) {
    { "id" => root_id, "channel_id" => channel, "user_id" => user_id, "root_id" => "", "message" => "@worker start",
      "create_at" => 1000, "update_at" => 1000, "delete_at" => 0, "props" => {}, "metadata" => { "embeds" => [] } }
  }
  let(:reply) {
    root.merge("id" => post_id, "root_id" => root_id, "message" => "ordinary human reply", "create_at" => 2000,
               "update_at" => 2000)
  }
  let(:responses) {
    { "/api/v4/posts/#{post_id}" => reply, "/api/v4/posts/#{root_id}" => root,
      "/api/v4/users/#{user_id}" => { "id" => user_id }, "/api/v4/channels/#{channel}/members/#{user_id}" => { "channel_id" => channel, "user_id" => user_id }, "/api/v4/channels/#{channel}" => { "id" => channel, "team_id" => "t" * 26 } }
  }
  # Explicit synthetic transport fixture at the Client boundary, not live API evidence.
  let(:client) {
    double.tap { |c|
      data = responses
      allow(c).to receive(:get) { |path| Marshal.load(Marshal.dump(data.fetch(path))) }
      allow(c).to receive(:parse) { |json| JSON.parse(json) }
    }
  }
  let(:api) { Adapters::Mattermost::Api.new(client: client) }
  let(:resolver) { Adapters::Mattermost::DeliveryVerifier.new(api: api, local_bot_ids: ["b" * 26]) }
  before do
    %i[callbacks sessions approvals reviews queued_messages workflows projects outbox inbox audit jobs
       chat_checkpoints].each { |t|
      db[t].delete
    }
  end
  let(:kinds) { Domains::Messaging::Dto::EventKind }
  let(:statuses) { Services::Inbound::Dto::IngestStatus }
  def verify(post = reply, kind = Domains::Messaging::Dto::EventKind::Posted)
    resolver.delivery(post_id: post["id"], channel_id: post["channel_id"], event_kind: kind)
  end
  it "refetches post/root/channel/user/membership and derives ordinary thread routing" do
    delivery = verify
    expect(delivery.thread_id).to eq(root_id)
    expect(delivery.actor.bot).to be(false) # authenticated REST omits is_bot:false
    expect(delivery.post_revision).to eq(2000)
  end
  it "rejects cross-channel roots, revoked membership and wrong is_bot types" do
    responses["/api/v4/posts/#{root_id}"]["channel_id"] = "x" * 26
    expect { verify }.to raise_error(ArgumentError)
    responses["/api/v4/posts/#{root_id}"]["channel_id"] = channel
    responses["/api/v4/channels/#{channel}/members/#{user_id}"]["user_id"] = "x" * 26
    expect { verify }.to raise_error(ArgumentError)
    responses["/api/v4/channels/#{channel}/members/#{user_id}"]["user_id"] = user_id
    responses["/api/v4/users/#{user_id}"]["is_bot"] = "false"
    expect { verify }.to raise_error(ArgumentError)
  end
  it "never trusts forged WebSocket user/bot claims" do
    fake = reply.merge("user_id" => "x" * 26, "is_bot" => false)
    event = { "event" => "posted", "data" => { "post" => JSON.generate(fake) },
              "broadcast" => { "channel_id" => channel }, "seq" => 10 }
    delivery = resolver.event(event)
    expect(delivery.actor.user_id).to eq(user_id)
    responses["/api/v4/users/#{user_id}"]["is_bot"] = true
    expect(resolver.event(event).actor.bot).to be(true)
  end
  it "rejects local bot loops even if REST says is_bot:false" do
    own = Adapters::Mattermost::DeliveryVerifier.new(api: api, local_bot_ids: [user_id])
    expect { own.delivery(post_id: post_id, channel_id: channel, event_kind: kinds::Posted) }.to raise_error(ArgumentError)
  end
  it "keeps a failed membership fetch retryable with its HTTP status" do
    allow(client).to receive(:get).with("/api/v4/channels/#{channel}/members/#{user_id}")
                                  .and_raise(Adapters::Mattermost::Errors::RequestFailed.new("Mattermost HTTP 404", status: 404))
    expect { verify }.to raise_error(Adapters::Mattermost::Errors::RequestFailed) { |error| expect(error.status).to eq(404) }
  end
  it "rejects deleted roots and revision timestamps with wrong types" do
    root["delete_at"] = 10
    expect { verify }.to raise_error(ArgumentError)
    root["delete_at"] = 0
    reply["update_at"] = "2000"
    expect { verify }.to raise_error(ArgumentError)
  end
  it "durably deduplicates inbox before dispatching and ignores unactivated ordinary replies" do
    router = Services::Inbound::RecordDelivery.new(agent_handle: "agent", worker_handle: "worker", master_channel_id: nil)
    2.times { router.call(delivery: verify) }
    expect(db[:inbox].count).to eq(1)
    expect(db[:jobs].count).to eq(0)
    result = router.call(delivery: verify(root)).result
    expect(result.status).to eq(statuses::Blocked) # Task1 early slice not passed
    expect(db[:jobs].count).to eq(1)
    expect(db[:jobs].first[:kind]).to eq("workflow.start")
  end
  it "deduplicates WS/backfill overlap without relying on socket seq" do
    router = Services::Inbound::RecordDelivery.new(agent_handle: "agent", worker_handle: "worker", master_channel_id: nil)
    event = { "event" => "posted", "data" => { "post" => JSON.generate(root) },
              "broadcast" => { "channel_id" => channel }, "seq" => 10 }
    2.times { router.call(delivery: resolver.event(event.merge("seq" => 20))) }
    expect(db[:inbox].count).to eq(1)
    expect(db[:jobs].count).to eq(1)
  end
  it "rejects bot starts/approvals and queues messages during paused/review phases" do
    db[:projects].insert(id: "p", channel_id: channel, slug: "owner/repo", remote_identity: "github.com/owner/repo",
                         workspace: "/tmp/fixture")
    db[:workflows].insert(id: "w", project_id: "p", channel_id: channel, thread_id: root_id, branch: "digitaltwin/w",
                          worktree_path: "/tmp/w", phase: "spec_review", role_configurations: workflow_roles)
    router = Services::Inbound::RecordDelivery.new(agent_handle: "agent", worker_handle: "worker", master_channel_id: nil)
    router.call(delivery: verify)
    expect(db[:queued_messages].count).to eq(1)
    expect(db[:outbox].count).to eq(1)
    expect(db[:jobs].exclude(kind: "mattermost.post").count).to eq(0)
    responses["/api/v4/users/#{user_id}"]["is_bot"] = true
    root["update_at"] = 3000
    expect(router.call(delivery: verify(root)).result.status).to eq(statuses::Rejected)
  end
  it "records edits without starting new workflow effects" do
    router = Services::Inbound::RecordDelivery.new(agent_handle: "agent", worker_handle: "worker", master_channel_id: nil)
    expect(router.call(delivery: verify(root, kinds::PostEdited)).result.status).to eq(statuses::Accepted)
    expect(db[:jobs].count).to eq(0)
  end
end

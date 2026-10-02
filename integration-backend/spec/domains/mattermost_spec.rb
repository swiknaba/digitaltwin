require_relative "../spec_helper"
RSpec.describe "Source-derived Mattermost adapter contracts (offline)" do
  let(:db) { Kirei::App.raw_db_connection }
  let(:channel) { "c" * 26 }
  let(:user_id) { "h" * 26 }
  let(:root_id) { "r" * 26 }
  let(:post_id) { "p" * 26 }
  let(:root) {
    { "id" => root_id, "channel_id" => channel, "user_id" => user_id, "root_id" => "", "message" => "@worker start",
      "create_at" => 1000, "update_at" => 1000, "delete_at" => 0 }
  }
  let(:reply) {
    root.merge("id" => post_id, "root_id" => root_id, "message" => "ordinary human reply", "create_at" => 2000,
               "update_at" => 2000)
  }
  let(:responses) {
    { "/api/v4/posts/#{post_id}" => reply, "/api/v4/posts/#{root_id}" => root,
      "/api/v4/users/#{user_id}" => { "id" => user_id }, "/api/v4/channels/#{channel}/members/#{user_id}" => { "channel_id" => channel, "user_id" => user_id }, "/api/v4/channels/#{channel}" => { "id" => channel, "team_id" => "t" * 26 } }
  }
  # Explicit synthetic transport fixture, not live API evidence.
  let(:client) {
    Object.new.tap { |c|
      data = responses; c.define_singleton_method(:get) { |path|
        Marshal.load(Marshal.dump(data.fetch(path)))
      }
      c.extend(Domains::Mattermost::VerifiedDelivery::Transport)
    }
  }
  let(:resolver) { Domains::Mattermost::ActorResolver.new(client, local_bot_ids: ["b" * 26]) }
  before do
    %i[callbacks sessions approvals reviews queued_messages workflows projects outbox inbox audit jobs
       chat_checkpoints].each { |t|
      db[t].delete
    }
  end
  def verify(post = reply, kind = "posted")
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
    own = Domains::Mattermost::ActorResolver.new(client, local_bot_ids: [user_id])
    expect { own.delivery(post_id: post_id, channel_id: channel, event_kind: "posted") }.to raise_error(ArgumentError)
  end
  it "rejects deleted roots and revision timestamps with wrong types" do
    root["delete_at"] = 10
    expect { verify }.to raise_error(ArgumentError)
    root["delete_at"] = 0
    reply["update_at"] = "2000"
    expect { verify }.to raise_error(ArgumentError)
  end
  it "durably deduplicates inbox before dispatching and ignores unactivated ordinary replies" do
    router = Domains::Mattermost::Router.new(db)
    2.times { router.ingest(delivery: verify) }
    expect(db[:inbox].count).to eq(1)
    expect(db[:jobs].count).to eq(0)
    result = router.ingest(delivery: verify(root))
    expect(result.status).to eq("blocked") # Task1 early slice not passed
    expect(db[:jobs].count).to eq(1)
    expect(db[:jobs].first[:kind]).to eq("workflow.start")
  end
  it "deduplicates WS/backfill overlap without relying on socket seq" do
    router = Domains::Mattermost::Router.new(db)
    event = { "event" => "posted", "data" => { "post" => JSON.generate(root) },
              "broadcast" => { "channel_id" => channel }, "seq" => 10 }
    2.times { router.ingest(delivery: resolver.event(event.merge("seq" => 20))) }
    expect(db[:inbox].count).to eq(1)
    expect(db[:jobs].count).to eq(1)
  end
  it "rejects bot starts/approvals and queues messages during paused/review phases" do
    db[:projects].insert(id: "p", channel_id: channel, slug: "owner/repo", remote_identity: "github.com/owner/repo",
                         workspace: "/tmp/fixture")
    db[:workflows].insert(id: "w", project_id: "p", channel_id: channel, thread_id: root_id, branch: "digitaltwin/w",
                          worktree_path: "/tmp/w", phase: "spec_review")
    router = Domains::Mattermost::Router.new(db)
    router.ingest(delivery: verify)
    expect(db[:queued_messages].count).to eq(1)
    expect(db[:outbox].count).to eq(1)
    expect(db[:jobs].exclude(kind: "mattermost.post").count).to eq(0)
    responses["/api/v4/users/#{user_id}"]["is_bot"] = true
    root["update_at"] = 3000
    expect(router.ingest(delivery: verify(root)).status).to eq("rejected")
  end
  it "records edits without starting new workflow effects" do
    router = Domains::Mattermost::Router.new(db)
    expect(router.ingest(delivery: verify(root, "post_edited")).status).to eq("accepted")
    expect(db[:jobs].count).to eq(0)
  end
end

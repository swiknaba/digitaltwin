require_relative "../../spec_helper"
RSpec.describe Services::Outbound::DeliverOutbox do
  let(:db) { Kirei::App.raw_db_connection }
  before do
    db[:outbox].delete; db[:jobs].delete
    @channel, @root, @bot = "c" * 26, "r" * 26, "b" * 26
    message = Domains::Messaging::Dto::OutgoingMessage.new(channel_id: @channel, thread_id: @root, bot: Domains::Messaging::Dto::Bot::Agent,
                                                           role: Domains::Messaging::Dto::SpeakerRole::Writer, body: "[writer] question", key: "response")
    @id = Domains::Messaging::Outbox.new.enqueue(message: message).result
    @gets = { "/api/v4/users/me" => { "id" => @bot, "is_bot" => true }, "/api/v4/channels/#{@channel}" => { "id" => @channel },
              "/api/v4/channels/#{@channel}/members/#{@bot}" => { "channel_id" => @channel, "user_id" => @bot },
              "/api/v4/posts/#{@root}" => { "id" => @root, "channel_id" => @channel, "user_id" => "h" * 26, "root_id" => "", "message" => "root",
                                            "create_at" => 1, "update_at" => 1, "delete_at" => 0 } }
    @calls = []
    gets, calls, bot = @gets, @calls, @bot
    # Synthetic transport fixture at the Client boundary.
    @client = double
    allow(@client).to receive(:get) { |path| gets.fetch(path) }
    allow(@client).to receive(:post) do |path, body|
      calls << [path, body]
      body.merge("id" => "p" * 26, "user_id" => bot, "create_at" => 2, "update_at" => 2, "delete_at" => 0)
    end
  end
  def apis = { Domains::Messaging::Dto::Bot::Agent => Adapters::Mattermost::Api.new(client: @client) }
  def bot_ids = { Domains::Messaging::Dto::Bot::Agent => @bot }
  def service = described_class.new(apis: apis, bot_ids: bot_ids)
  def reconcile = Services::Outbound::ReconcileOutbox.new(apis: apis, bot_ids: bot_ids)

  def run_delivery
    handler = service
    tick_job(Platform::Jobs::Dto::JobKind::MattermostPost) { |job| handler.call(job: job) }
  end
  it "verifies destination/identity before posting with thread and stable reconciliation key" do
    run_delivery
    expect(@calls.size).to eq(1)
    expect(@calls.first[1]).to eq("channel_id" => @channel, "root_id" => @root, "message" => "[writer] question",
                                  "props" => { "digitaltwin_response_key" => "response" })
    expect(db[:outbox][id: @id][:status]).to eq("delivered")
    expect(db[:outbox][id: @id][:remote_post_id]).to eq("p" * 26)
    expect(db[:jobs].first[:status]).to eq("complete")
  end
  it "never retries an unknown result" do
    allow(@client).to receive(:post).and_raise(IOError, "lost result")
    run_delivery
    run_delivery
    expect(db[:outbox][id: @id][:status]).to eq("uncertain")
    expect(db[:jobs].first[:status]).to eq("uncertain")
  end
  it "rejects another channel's root or a missing bot membership before starting the external effect" do
    @gets["/api/v4/posts/#{@root}"]["channel_id"] = "x" * 26
    run_delivery
    expect(@calls).to be_empty
    expect(db[:jobs].first[:effect_started_at]).to be_nil
    @gets["/api/v4/posts/#{@root}"]["channel_id"] = @channel
    allow(@client).to receive(:get).with("/api/v4/channels/#{@channel}/members/#{@bot}")
                                   .and_raise(Adapters::Mattermost::Errors::RequestFailed.new("Mattermost HTTP 404", status: 404))
    db[:jobs].update(available_at: Time.now - 1)
    run_delivery
    expect(@calls).to be_empty
    expect(db[:jobs].first[:effect_started_at]).to be_nil
  end
  it "reconciles a lost successful post only against verified server evidence" do
    body = nil
    calls = 0
    bot = @bot
    allow(@client).to receive(:post) do |_path, payload|
      calls += 1
      body = payload.merge("id" => "p" * 26, "user_id" => bot, "create_at" => 2, "update_at" => 2, "delete_at" => 0)
      raise IOError, "lost response after success"
    end
    run_delivery
    row = db[:outbox][id: @id]
    since = [(row[:created_at].to_time.to_f * 1000).to_i - 1000, 1].max
    path = "/api/v4/channels/#{@channel}/posts?since=#{since}&collapsedThreads=false"
    @gets[path] = { "order" => ["p" * 26], "posts" => { "p" * 26 => body.merge("props" => body["props"].merge("unrelated" => "x"), "metadata" => {}) } }
    expect(reconcile.call(outbox_id: @id).result).to eq(Domains::Messaging::Dto::OutboxStatus::Delivered)
    expect(db[:outbox][id: @id][:status]).to eq("delivered")
    expect(db[:jobs].first[:status]).to eq("complete")
    expect(calls).to eq(1)
    failure = reconcile.call(outbox_id: @id).errors.first
    expect([failure&.code, failure&.detail]).to eq(["not_uncertain", "Expected uncertain delivery"])
  end

  it "keeps an uncertain delivery uncertain without exactly one server match" do
    allow(@client).to receive(:post).and_raise(IOError, "lost result")
    run_delivery
    since = [(db[:outbox][id: @id][:created_at].to_time.to_f * 1000).to_i - 1000, 1].max
    @gets["/api/v4/channels/#{@channel}/posts?since=#{since}&collapsedThreads=false"] = { "order" => [], "posts" => {} }
    expect(reconcile.call(outbox_id: @id).result).to eq(Domains::Messaging::Dto::OutboxStatus::Uncertain)
    expect(db[:outbox][id: @id][:status]).to eq("uncertain")
    expect(db[:jobs].first[:status]).to eq("uncertain")
  end
end

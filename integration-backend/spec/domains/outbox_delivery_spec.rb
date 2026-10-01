require_relative "../spec_helper"
RSpec.describe "Mattermost outbox delivery (synthetic transport)" do
  let(:db) { Kirei::App.raw_db_connection }
  before do
    db[:outbox].delete; db[:jobs].delete
    @channel, @root, @bot = "c" * 26, "r" * 26, "b" * 26
    @id = Domains::Mattermost::Outbox.new(db).enqueue(channel_id: @channel, thread_id: @root, bot: "worker", role: "writer",
                                                      body: "[writer] question", key: "response")
    @gets = { "/api/v4/users/me" => { "id" => @bot, "is_bot" => true }, "/api/v4/channels/#{@channel}" => { "id" => @channel },
              "/api/v4/channels/#{@channel}/members/#{@bot}" => { "channel_id" => @channel, "user_id" => @bot }, "/api/v4/posts/#{@root}" => { "id" => @root, "channel_id" => @channel, "root_id" => "", "delete_at" => 0 } }
    @calls = []
    fixture = self
    @client = Object.new
    @client.define_singleton_method(:get) { |path| fixture.instance_variable_get(:@gets).fetch(path) }
    @client.define_singleton_method(:post) do |path, body|
      fixture.instance_variable_get(:@calls) << [path, body]
      body.merge("id" => "p" * 26, "user_id" => fixture.instance_variable_get(:@bot))
    end
  end
  def run_delivery
    handler = Domains::Mattermost::Delivery.new(db, clients: { "worker" => @client }, bot_ids: { "worker" => @bot })
    Async { Domains::Jobs::Worker.new(db, handlers: { "mattermost.post" => handler.method(:call) }).tick }.wait
  end
  it "verifies destination/identity before posting with thread and stable reconciliation key" do
    run_delivery
    expect(@calls.size).to eq(1)
    expect(@calls.first[1]).to include("channel_id" => @channel, "root_id" => @root, "message" => "[writer] question",
                                       "props" => { "digitaltwin_response_key" => "response" })
    expect(db[:outbox][id: @id][:status]).to eq("delivered")
    expect(db[:jobs].first[:status]).to eq("complete")
  end
  it "never retries an unknown result" do
    @client.define_singleton_method(:post) { |*| raise IOError, "lost result" }
    run_delivery
    run_delivery
    expect(db[:outbox][id: @id][:status]).to eq("uncertain")
    expect(db[:jobs].first[:status]).to eq("uncertain")
  end
  it "rejects another channel's root before starting the external effect" do
    @gets["/api/v4/posts/#{@root}"]["channel_id"] = "x" * 26
    run_delivery
    expect(@calls).to be_empty
    expect(db[:jobs].first[:effect_started_at]).to be_nil
  end
  it "reconciles a lost successful post only against verified server evidence" do
    body = nil
    calls = 0
    bot = @bot
    @client.define_singleton_method(:post) do |_path, payload|
      calls += 1
      body = payload.merge("id" => "p" * 26, "user_id" => bot)
      raise IOError, "lost response after success"
    end
    run_delivery
    row = db[:outbox][id: @id]
    since = [(row[:created_at].to_time.to_f * 1000).to_i - 1000, 1].max
    path = "/api/v4/channels/#{@channel}/posts?since=#{since}&collapsedThreads=false"
    @gets[path] = { "posts" => { "p" * 26 => body } }
    service = Domains::Mattermost::Delivery.new(db, clients: { "worker" => @client }, bot_ids: { "worker" => @bot })
    expect(service.reconcile(outbox_id: @id)).to be(true)
    expect(db[:outbox][id: @id][:status]).to eq("delivered")
    expect(db[:jobs].first[:status]).to eq("complete")
    expect(calls).to eq(1)
  end
end

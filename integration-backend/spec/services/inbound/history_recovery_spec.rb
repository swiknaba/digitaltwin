require_relative "../../spec_helper"

RSpec.describe Services::Inbound::HistoryRecovery do
  let(:db) { Kirei::App.raw_db_connection }
  let(:channel) { "c" * 26 }
  let(:human) { "h" * 26 }
  let(:bot) { "b" * 26 }

  def post(id, user, revision)
    { "id" => id * 26, "channel_id" => channel, "user_id" => user, "root_id" => "",
      "message" => "@agent fixture", "create_at" => revision, "update_at" => revision, "delete_at" => 0 }
  end

  before do
    @posts = [post("a", bot, 1000), post("d", human, 2000), post("e", human, 3000)]
    @responses = { "/api/v4/channels/#{channel}" => { "id" => channel } }
    [human, bot].each do |id|
      @responses["/api/v4/users/#{id}"] = { "id" => id, "is_bot" => id == bot }
      @responses["/api/v4/channels/#{channel}/members/#{id}"] = { "channel_id" => channel, "user_id" => id }
    end
    @posts.each { |p| @responses["/api/v4/posts/#{p["id"]}"] = p }
    fixture = self
    @client = double
    allow(@client).to receive(:get) { |path| fixture.request(path) }
    api = Adapters::Mattermost::Api.new(client: @client)
    @resolver = Adapters::Mattermost::DeliveryVerifier.new(api: api, local_bot_ids: [bot])
    @service = Services::Inbound::HistoryRecovery.new(api: api, verifier: @resolver, router: Services::Inbound::RecordDelivery.new)
    @fail_post = nil
  end

  def request(path)
    if path.start_with?("/api/v4/channels/#{channel}/posts?")
      since = URI.decode_www_form(URI.parse(path).query).to_h.fetch("since").to_i
      selected = @filter_since ? @posts.select { |p| [p["create_at"], p["update_at"], p["delete_at"]].max > since } : @posts
      selected = selected.first(1000) if @upstream_cap && since.positive?
      { "order" => selected.map { |p| p.fetch("id") }, "posts" => selected.to_h { |p| [p.fetch("id"), p] } }
    elsif path == @fail_post
      raise Adapters::Mattermost::Errors::RequestFailed, "Temporary fixture failure"
    else
      @responses.fetch(path)
    end
  end

  it "survives reconnect history with own bots and forged or malformed candidates" do
    @posts << post("f", human, 9000).merge("channel_id" => "x" * 26)
    @posts << post("g", human, 9001).merge("update_at" => "forged")
    2.times { expect(@service.call(channel_id: channel)).to eq(3000) }
    expect(db[:inbox].count).to eq(2)
    expect(db[:jobs].count).to eq(2)
    expect(db[:audit].where(action: "history_rejected").count).to eq(3)
    expect(db[:chat_checkpoints][channel_id: channel][:post_revision]).to eq(3000)
    forged = @posts.find { |p| p["update_at"] == "forged" }
    digest = Digest::SHA256.hexdigest(JSON.generate([channel, forged]))
    expect(db[:audit][event_key: "history-rejected:#{digest}"][:details].to_hash).to eq("reason" => "Malformed history post")
  end

  it "retries transient fetch failure without advancing past an unprocessed item" do
    db[:chat_checkpoints].insert(channel_id: channel, post_revision: 1500)
    @fail_post = "/api/v4/posts/#{"e" * 26}"
    expect { @service.call(channel_id: channel) }.to raise_error(Adapters::Mattermost::Errors::RequestFailed)
    expect(db[:chat_checkpoints][channel_id: channel][:post_revision]).to eq(1500)
    expect(db[:inbox].count).to eq(1)
    @fail_post = nil
    expect(@service.call(channel_id: channel)).to eq(3000)
    expect(db[:inbox].count).to eq(2)
    expect(db[:jobs].count).to eq(2)
  end

  it "retains the checkpoint when positive-since recovery reaches the unordered upstream cap" do
    db[:chat_checkpoints].insert(channel_id: channel, post_revision: 1500)
    @upstream_cap = true
    @posts = 1010.times.map do |i|
      post("z", human, 2000 + i).merge("id" => i.to_s(36).rjust(26, "0"))
    end
    2.times do
      expect { @service.call(channel_id: channel) }.to raise_error(Services::Inbound::HistoryRecovery::RecoveryRequired, /1000-post cap.*operator recovery/)
    end
    expect(db[:chat_checkpoints][channel_id: channel][:post_revision]).to eq(1500)
    expect(db[:inbox].count).to eq(0)
  end

  it "uses the covered history revision across a later refetch edit and reconnect" do
    @filter_since = true
    db[:chat_checkpoints].insert(channel_id: channel, post_revision: 1500)
    @responses["/api/v4/posts/#{"d" * 26}"] = post("d", human, 2000).merge("update_at" => 10000)
    expect(@service.call(channel_id: channel)).to eq(3000)
    expect(db[:inbox].where(post_id: "d" * 26).first[:post_revision]).to eq(10000)
    @posts = [post("f", human, 5000), @responses["/api/v4/posts/#{"d" * 26}"]]
    @responses["/api/v4/posts/#{"f" * 26}"] = @posts.first
    expect(@service.call(channel_id: channel)).to eq(10000)
    expect(db[:inbox].where(post_id: "f" * 26).count).to eq(1)
    expect(@service.call(channel_id: channel)).to eq(10000)
    expect(db[:inbox].where(post_id: "f" * 26).count).to eq(1)
  end
end

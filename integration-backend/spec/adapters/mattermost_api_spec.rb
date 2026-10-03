require_relative "../spec_helper"
RSpec.describe Adapters::Mattermost::Api do
  let(:channel) { "c" * 26 }
  let(:user) { "u" * 26 }
  let(:post) do
    { "id" => "p" * 26, "channel_id" => channel, "user_id" => user, "root_id" => "", "message" => "hello", "create_at" => 1, "update_at" => 2, "delete_at" => 0,
      "props" => { "digitaltwin_response_key" => "key", "digitaltwin_count" => 3, "from_bot" => "true" }, "metadata" => { "embeds" => [] } }
  end
  # Synthetic transport fixture at the Client boundary.
  let(:client) { double }
  let(:api) { described_class.new(client: client) }

  it "translates posts and keeps only digitaltwin String props" do
    allow(client).to receive(:get).with("/api/v4/posts/#{"p" * 26}").and_return(post)
    expect(api.post("p" * 26)).to eq(Adapters::Mattermost::Dto::Post.new(id: "p" * 26, channel_id: channel, user_id: user, root_id: "", message: "hello",
                                                                         create_at: 1, update_at: 2, delete_at: 0, props: { "digitaltwin_response_key" => "key" }))
    allow(client).to receive(:get).with("/api/v4/posts/#{"p" * 26}").and_return(post.merge("update_at" => "2"))
    expect { api.post("p" * 26) }.to raise_error(Adapters::Mattermost::Errors::MalformedResponse, "Invalid post revision")
    allow(client).to receive(:get).with("/api/v4/posts/#{"p" * 26}").and_return(post.merge("props" => "none"))
    expect { api.post("p" * 26) }.to raise_error(ArgumentError, "Malformed server response")
    expect { api.post("../users/me") }.to raise_error(ArgumentError, "Invalid Mattermost identifier")
  end

  it "defaults omitted user fields and rejects non-boolean bot status" do
    allow(client).to receive(:get).with("/api/v4/users/me").and_return({ "id" => user })
    expect(api.me).to eq(Adapters::Mattermost::Dto::User.new(id: user, delete_at: 0, bot: false))
    allow(client).to receive(:get).with("/api/v4/users/#{user}").and_return({ "id" => user, "is_bot" => "false" })
    expect { api.user(user) }.to raise_error(Adapters::Mattermost::Errors::MalformedResponse, "Unverified bot status")
  end

  it "returns nil membership on 404, transport failure and invalid identifiers, but member! keeps the status" do
    path = "/api/v4/channels/#{channel}/members/#{user}"
    allow(client).to receive(:get).with(path).and_return({ "channel_id" => channel, "user_id" => user })
    expect(api.member(channel_id: channel, user_id: user)).to eq(Adapters::Mattermost::Dto::ChannelMember.new(channel_id: channel, user_id: user))
    allow(client).to receive(:get).with(path).and_raise(Adapters::Mattermost::Errors::RequestFailed.new("Mattermost HTTP 404", status: 404))
    expect(api.member(channel_id: channel, user_id: user)).to be_nil
    expect { api.member!(channel_id: channel, user_id: user) }.to raise_error(Adapters::Mattermost::Errors::RequestFailed) { |error| expect(error.status).to eq(404) }
    allow(client).to receive(:get).with(path).and_raise(Adapters::Mattermost::Errors::RequestFailed, "Mattermost response too large")
    expect(api.member(channel_id: channel, user_id: user)).to be_nil
    expect(api.member(channel_id: "x", user_id: user)).to be_nil
  end

  it "posts the typed payload and translates the created post" do
    new_post = Adapters::Mattermost::Dto::NewPost.new(channel_id: channel, root_id: "", message: "hello", props: { "digitaltwin_response_key" => "key" })
    expect(client).to receive(:post).with("/api/v4/posts", { "channel_id" => channel, "root_id" => "", "message" => "hello", "props" => { "digitaltwin_response_key" => "key" } }).and_return(post)
    expect(api.create_post(new_post).props).to eq("digitaltwin_response_key" => "key")
  end

  it "builds history queries and keeps rejected posts with their received JSON" do
    bad = post.merge("id" => "b" * 26, "user_id" => 7)
    paged = "/api/v4/channels/#{channel}/posts?since=0&collapsedThreads=false&page=2&per_page=200"
    allow(client).to receive(:get).with(paged).and_return({ "order" => ["p" * 26, "b" * 26], "posts" => { "p" * 26 => post, "b" * 26 => bad } })
    page = api.channel_history(channel_id: channel, since: 0, page: 2)
    expect(page.order).to eq(["p" * 26, "b" * 26])
    good, rejected = page.entries
    expect(good.post&.id).to eq("p" * 26)
    expect([rejected.post, rejected.rejection, rejected.post_id, rejected.canonical_json]).to eq([nil, "Malformed history post", "b" * 26, JSON.generate(bad)])
    unpaged = "/api/v4/channels/#{channel}/posts?since=5&collapsedThreads=false"
    allow(client).to receive(:get).with(unpaged).and_return({ "posts" => {} })
    expect { api.channel_history(channel_id: channel, since: 5, page: nil) }.to raise_error(Adapters::Mattermost::Errors::RequestFailed, /envelope/)
  end
end

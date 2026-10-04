# typed: strict
# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe Services::Inbound::ChatListener do
  let(:client) { Adapters::Mattermost::Client.new(url: "http://fixture.invalid", token_file: "/unused") }
  let(:api) { Adapters::Mattermost::Api.new(client: client) }
  let(:listener) do
    described_class.new(client: client, api: api, verifier: Adapters::Mattermost::DeliveryVerifier.new(api: api), channels: [],
                        router: Services::Inbound::RecordDelivery.new(agent_handle: "agent", worker_handle: "worker", commander_channel_id: nil),
                        validation_mode: true, heartbeat_dir: "/tmp")
  end

  it "reads the actual TextMessage buffer rather than Object#to_s" do
    socket = double("socket", read: Protocol::WebSocket::TextMessage.new('{"status":"OK"}'))
    expect(listener.send(:read_text, socket)).to eq('{"status":"OK"}')
  end

  it "rejects binary frames and closed sockets" do
    binary = double("socket", read: Protocol::WebSocket::BinaryMessage.new("not text"))
    closed = double("socket", read: nil)
    expect { listener.send(:read_text, binary) }.to raise_error(Adapters::Mattermost::Errors::RequestFailed)
    expect { listener.send(:read_text, closed) }.to raise_error(EOFError)
  end

  it "skips hello and accepts the correlated acknowledgment with nested metadata" do
    expect(listener.send(:parse_auth, JSON.generate(event: "hello", data: { server_version: "fixture" }, broadcast: { omit_users: nil }))).to eq({})
    expect(listener.send(:parse_auth, JSON.generate(status: "OK", seq_reply: 1, data: {}))).to eq({ "status" => "OK", "seq_reply" => 1 })
    expect { listener.send(:parse_auth, JSON.generate(status: true, seq_reply: 1)) }.to raise_error(Adapters::Mattermost::Errors::RequestFailed)
  end

  it "retains only verified post/channel hints from heterogeneous metadata" do
    frame = JSON.generate(event: "posted", data: { post: "fixture-post", unrelated: true },
                          broadcast: { channel_id: "fixture-channel", omit_users: nil, contains_sanitized_data: false }, seq: 3)
    expect(listener.send(:parse_event, frame)).to eq({ "event" => "posted", "data" => { "post" => "fixture-post" }, "broadcast" => { "channel_id" => "fixture-channel" } })
    expect { listener.send(:parse_event, JSON.generate(event: "posted", data: { post: 1 })) }.to raise_error(Adapters::Mattermost::Errors::RequestFailed)
    expect { listener.send(:parse_event, JSON.generate(event: "posted", data: { post: "fixture" }, broadcast: { channel_id: true })) }.to raise_error(Adapters::Mattermost::Errors::RequestFailed)
  end
end

# typed: strict
# frozen_string_literal: true

module Services
  module Inbound
    # Receives WebSocket hints, then asks the authenticated REST adapter to verify them.
    class ChatListener
      extend T::Sig

      AuthEnvelope = T.type_alias { T::Hash[String, T.any(String, Integer)] }
      EventEnvelope = T.type_alias { Adapters::Mattermost::DeliveryVerifier::EventEnvelope }
      RequestFailed = Adapters::Mattermost::Errors::RequestFailed

      sig { params(db: Sequel::Database).returns(ChatListener) }
      def self.from_env(db)
        client = Adapters::Mattermost::Client.new(url: ENV.fetch("MATTERMOST_URL"), token_file: ENV.fetch("MATTERMOST_LISTENER_TOKEN_FILE"))
        api = Adapters::Mattermost::Api.new(client: client)
        verifier = Adapters::Mattermost::DeliveryVerifier.new(api: api, local_bot_ids: ENV.fetch("MATTERMOST_LOCAL_BOT_IDS").split(","),
                                                              peer_bot_ids: ENV.fetch("MATTERMOST_PEER_BOT_IDS", "").split(","))
        new(db, client: client, api: api, verifier: verifier, channels: ENV.fetch("MATTERMOST_CHANNEL_IDS").split(","))
      end

      sig do
        params(db: Sequel::Database, client: Adapters::Mattermost::Client, api: Adapters::Mattermost::Api,
               verifier: Adapters::Mattermost::DeliveryVerifier, channels: T::Array[String]).void
      end
      def initialize(db, client:, api:, verifier:, channels:)
        @db = T.let(db, Sequel::Database)
        @client = T.let(client, Adapters::Mattermost::Client)
        @api = T.let(api, Adapters::Mattermost::Api)
        @verifier = T.let(verifier, Adapters::Mattermost::DeliveryVerifier)
        @channels = T.let(channels, T::Array[String])
        @router = T.let(Domains::Mattermost::Router.new(db), Domains::Mattermost::Router)
        @channels.each { |channel_id| @verifier.identifier!(channel_id) }
      end

      sig { returns(T.noreturn) }
      def call
        raise "Chat transport live evidence pending; set CHAT_VALIDATION_MODE=1 only for disposable validation" unless ENV["CHAT_VALIDATION_MODE"] == "1"

        delay = T.let(1, Integer)
        loop do
          begin
            endpoint = Async::HTTP::Endpoint.parse(websocket_url)
            Async::WebSocket::Client.connect(endpoint) do |socket|
              authenticate!(socket)
              recovery = HistoryRecovery.new(@db, api: @api, verifier: @verifier, router: @router)
              @channels.each { |channel_id| recovery.call(channel_id: channel_id) }
              delay = 1
              Health.touch("chat-listener")
              consume(socket)
            end
          rescue HistoryRecovery::RecoveryRequired => error
            warn error.message
            Async::Task.current.sleep(30)
          rescue RequestFailed, IOError, Async::TimeoutError, SystemCallError, JSON::ParserError
            warn "Mattermost listener disconnected; reconnecting with durable backfill"
            Async::Task.current.sleep(delay)
            delay = [delay * 2, 30].min
          end
        end
      end

      sig { returns(String) }
      private def websocket_url
        "#{@client.url.sub(/^http/, "ws")}/api/v4/websocket"
      end

      sig { params(socket: Async::WebSocket::Connection).void }
      private def authenticate!(socket)
        socket.write(JSON.generate({ seq: 1, action: "authentication_challenge", data: { token: @client.token } }))
        socket.flush
        auth = Async::Task.current.with_timeout(10) do
          loop do
            value = parse_auth(socket.read.to_s)
            break value if value["seq_reply"] == 1
          end
        end
        raise RequestFailed, "WebSocket authentication failed" unless auth["status"] == "OK" && auth["seq_reply"] == 1
      end

      sig { params(socket: Async::WebSocket::Connection).returns(T.noreturn) }
      private def consume(socket)
        loop do
          message = Async::Task.current.with_timeout(30) { socket.read }
          raise EOFError, "WebSocket closed" unless message

          ingest_envelope(parse_event(message.to_s))
          Health.touch("chat-listener")
        end
      end

      sig { params(envelope: EventEnvelope).void }
      private def ingest_envelope(envelope)
        return unless Adapters::Mattermost::DeliveryVerifier::KINDS.include?(envelope["event"])

        delivery = @verifier.event(envelope)
        return unless @channels.include?(delivery.channel_id)

        @router.ingest(delivery: delivery)
      rescue ArgumentError, RequestFailed
        warn "Rejected unverified Mattermost event; REST reconciliation remains required"
      end

      sig { params(json: String).returns(AuthEnvelope) }
      private def parse_auth(json)
        parsed = JSON.parse(json)
        raise RequestFailed, "Malformed WebSocket authentication response" unless parsed.is_a?(Hash)

        envelope = T.let({}, AuthEnvelope)
        parsed.each do |key, value|
          raise RequestFailed, "Malformed WebSocket authentication response" unless key.is_a?(String) && (value.is_a?(String) || value.is_a?(Integer))

          envelope[key] = value
        end
        envelope
      end

      sig { params(json: String).returns(EventEnvelope) }
      private def parse_event(json)
        parsed = JSON.parse(json)
        raise RequestFailed, "Malformed WebSocket event" unless parsed.is_a?(Hash)

        envelope = T.let({}, EventEnvelope)
        parsed.each do |key, value|
          raise RequestFailed, "Malformed WebSocket event" unless key.is_a?(String) && event_value?(value)

          envelope[key] = value
        end
        envelope
      end

      sig { params(value: Object).returns(T::Boolean) }
      private def event_value?(value)
        value.is_a?(String) || value.is_a?(Integer) ||
          (value.is_a?(Hash) && value.all? { |key, item| key.is_a?(String) && item.is_a?(String) })
      end
    end
  end
end

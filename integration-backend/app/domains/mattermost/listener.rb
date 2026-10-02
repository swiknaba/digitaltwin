# typed: strict
# frozen_string_literal: true

require "async/http/endpoint"
require "async/websocket/client"

module Domains
  module Mattermost
    # Receives websocket hints, then asks the authenticated REST adapter to verify them.
    class Listener
      extend T::Sig

      AuthEnvelope = T.type_alias { T::Hash[String, T.any(String, Integer)] }

      class VerificationTransport
        include VerifiedDelivery::Transport
        extend T::Sig

        sig { params(client: Client).void }
        def initialize(client)
          @client = T.let(client, Client)
        end

        sig { override.params(path: String).returns(VerifiedDelivery::TransportResponse) }
        def get(path)
          raw = @client.get(path)
          response = T.let({}, VerifiedDelivery::TransportResponse)
          raw.each do |key, value|
            response[key] = verification_value(value)
          end
          response
        end

        private

        sig { params(value: Object).returns(VerifiedDelivery::TransportValue) }
        def verification_value(value)
          return value if value.is_a?(String) || value.is_a?(Integer) || value == true || value == false || value.nil?

          raise Client::Error, "Malformed Mattermost verification response"
        end
      end

      sig { params(db: Sequel::Database).returns(Listener) }
      def self.from_env(db)
        client = Client.new(url: ENV.fetch("MATTERMOST_URL"), token_file: ENV.fetch("MATTERMOST_LISTENER_TOKEN_FILE"))
        local_bot_ids = ENV.fetch("MATTERMOST_LOCAL_BOT_IDS").split(",")
        resolver = ActorResolver.new(VerificationTransport.new(client), local_bot_ids: local_bot_ids,
                                                                        peer_bot_ids: ENV.fetch("MATTERMOST_PEER_BOT_IDS", "").split(","))
        new(db, client: client, resolver: resolver, channels: ENV.fetch("MATTERMOST_CHANNEL_IDS").split(","))
      end

      sig { params(db: Sequel::Database, client: Client, resolver: ActorResolver, channels: T::Array[String]).void }
      def initialize(db, client:, resolver:, channels:)
        @db = T.let(db, Sequel::Database)
        @client = T.let(client, Client)
        @resolver = T.let(resolver, ActorResolver)
        @channels = T.let(channels, T::Array[String])
        @router = T.let(Router.new(db), Router)
        @channels.each { |channel_id| @resolver.identifier!(channel_id) }
      end

      sig { returns(T.noreturn) }
      def run
        raise "Chat transport live evidence pending; set CHAT_VALIDATION_MODE=1 only for disposable validation" unless ENV["CHAT_VALIDATION_MODE"] == "1"

        delay = T.let(1, Integer)
        loop do
          begin
            endpoint = Async::HTTP::Endpoint.parse(websocket_url)
            Async::WebSocket::Client.connect(endpoint) do |socket|
              authenticate!(socket)
              reconciliation = Reconcile.new(@db, client: @client, resolver: @resolver, router: @router)
              @channels.each { |channel_id| reconciliation.channel(channel_id) }
              delay = 1
              Health.touch("chat-listener")
              consume(socket)
            end
          rescue Reconcile::RecoveryRequired => error
            warn error.message
            Async::Task.current.sleep(30)
          rescue Client::Error, IOError, Async::TimeoutError, SystemCallError, JSON::ParserError
            warn "Mattermost listener disconnected; reconnecting with durable backfill"
            Async::Task.current.sleep(delay)
            delay = [delay * 2, 30].min
          end
        end
      end

      private

      sig { returns(String) }
      def websocket_url
        "#{@client.url.sub(/^http/, "ws")}/api/v4/websocket"
      end

      sig { params(socket: Async::WebSocket::Connection).void }
      def authenticate!(socket)
        socket.write(JSON.generate({ seq: 1, action: "authentication_challenge", data: { token: @client.token } }))
        socket.flush
        auth = Async::Task.current.with_timeout(10) do
          loop do
            value = parse_auth(socket.read.to_s)
            break value if value["seq_reply"] == 1
          end
        end
        raise Client::Error, "WebSocket authentication failed" unless auth["status"] == "OK" && auth["seq_reply"] == 1
      end

      sig { params(socket: Async::WebSocket::Connection).returns(T.noreturn) }
      def consume(socket)
        loop do
          message = Async::Task.current.with_timeout(30) { socket.read }
          raise EOFError, "WebSocket closed" unless message

          ingest_envelope(parse_event(message.to_s))
          Health.touch("chat-listener")
        end
      end

      sig { params(envelope: ActorResolver::EventEnvelope).void }
      def ingest_envelope(envelope)
        return unless ActorResolver::KINDS.include?(envelope["event"])

        delivery = @resolver.event(envelope)
        return unless @channels.include?(delivery.channel_id)

        @router.ingest(delivery: delivery)
      rescue ArgumentError, Client::Error
        warn "Rejected unverified Mattermost event; REST reconciliation remains required"
      end

      sig { params(json: String).returns(AuthEnvelope) }
      def parse_auth(json)
        parsed = JSON.parse(json)
        raise Client::Error, "Malformed WebSocket authentication response" unless parsed.is_a?(Hash)

        envelope = T.let({}, AuthEnvelope)
        parsed.each do |key, value|
          raise Client::Error, "Malformed WebSocket authentication response" unless key.is_a?(String) && (value.is_a?(String) || value.is_a?(Integer))

          envelope[key] = value
        end
        envelope
      end

      sig { params(json: String).returns(ActorResolver::EventEnvelope) }
      def parse_event(json)
        parsed = JSON.parse(json)
        raise Client::Error, "Malformed WebSocket event" unless parsed.is_a?(Hash)

        envelope = T.let({}, ActorResolver::EventEnvelope)
        parsed.each do |key, value|
          raise Client::Error, "Malformed WebSocket event" unless key.is_a?(String) && event_value?(value)

          envelope[key] = value
        end
        envelope
      end

      sig { params(value: Object).returns(T::Boolean) }
      def event_value?(value)
        value.is_a?(String) || value.is_a?(Integer) ||
          (value.is_a?(Hash) && value.all? { |key, item| key.is_a?(String) && item.is_a?(String) })
      end
    end
  end
end

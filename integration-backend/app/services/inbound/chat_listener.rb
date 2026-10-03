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

      sig do
        params(client: Adapters::Mattermost::Client, api: Adapters::Mattermost::Api, verifier: Adapters::Mattermost::DeliveryVerifier,
               channels: T::Array[String], router: RecordDelivery, validation_mode: T::Boolean, heartbeat_dir: String).void
      end
      def initialize(client:, api:, verifier:, channels:, router:, validation_mode:, heartbeat_dir:)
        @validation_mode = validation_mode
        @heartbeat_dir = heartbeat_dir
        @client = T.let(client, Adapters::Mattermost::Client)
        @api = T.let(api, Adapters::Mattermost::Api)
        @verifier = T.let(verifier, Adapters::Mattermost::DeliveryVerifier)
        @channels = T.let(channels, T::Array[String])
        @router = T.let(router, RecordDelivery)
        @channels.each { |channel_id| @verifier.identifier!(channel_id) }
      end

      sig { returns(T.noreturn) }
      def call
        raise "Chat transport live evidence pending; set CHAT_VALIDATION_MODE=1 only for disposable validation" unless @validation_mode

        delay = T.let(1, Integer)
        loop do
          begin
            endpoint = Async::HTTP::Endpoint.parse(websocket_url)
            Async::WebSocket::Client.connect(endpoint) do |socket|
              authenticate!(socket)
              recovery = HistoryRecovery.new(api: @api, verifier: @verifier, router: @router)
              @channels.each { |channel_id| recovery.call(channel_id: channel_id) }
              delay = 1
              Platform::Heartbeat.touch(role: Platform::Heartbeat::Role::ChatListener, dir: @heartbeat_dir)
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
            value = parse_auth(read_text(socket))
            break value if value["seq_reply"] == 1
          end
        end
        raise RequestFailed, "WebSocket authentication failed" unless auth["status"] == "OK" && auth["seq_reply"] == 1
      end

      sig { params(socket: Async::WebSocket::Connection).returns(T.noreturn) }
      private def consume(socket)
        loop do
          message = Async::Task.current.with_timeout(30) { read_text(socket) }
          ingest_envelope(parse_event(message))
          Platform::Heartbeat.touch(role: Platform::Heartbeat::Role::ChatListener, dir: @heartbeat_dir)
        end
      end

      sig { params(envelope: EventEnvelope).void }
      private def ingest_envelope(envelope)
        return unless Adapters::Mattermost::DeliveryVerifier::KINDS.include?(envelope["event"])

        delivery = @verifier.event(envelope)
        return unless @channels.include?(delivery.channel_id)

        @router.call(delivery: delivery)
      rescue ArgumentError, RequestFailed
        warn "Rejected unverified Mattermost event; REST reconciliation remains required"
      end

      # The locked protocol-websocket Message exposes its payload through to_str;
      # Object#to_s prints an object description instead of JSON.
      sig { params(socket: Async::WebSocket::Connection).returns(String) }
      private def read_text(socket)
        message = T.let(socket.read, Object)
        raise EOFError, "WebSocket closed" if message.nil?
        raise RequestFailed, "Expected WebSocket text message" unless message.is_a?(Protocol::WebSocket::TextMessage)

        text = T.let(message.to_str, Object)
        raise RequestFailed, "Malformed WebSocket text buffer" unless text.is_a?(String)

        text
      end

      sig { params(json: String).returns(AuthEnvelope) }
      private def parse_auth(json)
        parsed = JSON.parse(json)
        raise RequestFailed, "Malformed WebSocket authentication response" unless parsed.is_a?(Hash)

        # Mattermost can send hello before the correlated acknowledgment, whose
        # unrelated data field is a nested object. Only these fields prove auth.
        return T.let({}, AuthEnvelope) unless parsed.key?("seq_reply")

        sequence = parsed["seq_reply"]
        status = parsed["status"]
        raise RequestFailed, "Malformed WebSocket authentication response" unless sequence.is_a?(Integer) && status.is_a?(String)

        { "seq_reply" => sequence, "status" => status }
      end

      sig { params(json: String).returns(EventEnvelope) }
      private def parse_event(json)
        parsed = JSON.parse(json)
        raise RequestFailed, "Malformed WebSocket event" unless parsed.is_a?(Hash)

        kind = parsed["event"]
        raise RequestFailed, "Malformed WebSocket event" unless kind.is_a?(String)

        envelope = T.let({ "event" => kind }, EventEnvelope)
        return envelope unless Adapters::Mattermost::DeliveryVerifier::KINDS.include?(kind)

        data = parsed["data"]
        raise RequestFailed, "Malformed WebSocket event data" unless data.is_a?(Hash)

        post = data["post"]
        raise RequestFailed, "Malformed WebSocket event post" unless post.is_a?(String)

        envelope["data"] = { "post" => post }
        broadcast = parsed["broadcast"]
        unless broadcast.nil?
          raise RequestFailed, "Malformed WebSocket broadcast" unless broadcast.is_a?(Hash)

          channel = broadcast["channel_id"]
          raise RequestFailed, "Malformed WebSocket broadcast channel" unless channel.nil? || channel.is_a?(String)

          # Boolean/null broadcast metadata is not authority. Retain only the
          # channel hint, which DeliveryVerifier checks against authenticated REST.
          envelope["broadcast"] = { "channel_id" => channel } if channel
        end
        envelope
      end
    end
  end
end

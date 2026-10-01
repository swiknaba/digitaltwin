# frozen_string_literal: true

require "async/websocket/client"
require "async/http/endpoint"
module Domains
  module Mattermost
    class Listener
      def self.from_env(db)
        client = Client.new(url: ENV.fetch("MATTERMOST_URL"), token_file: ENV.fetch("MATTERMOST_LISTENER_TOKEN_FILE"))
        own = ENV.fetch("MATTERMOST_LOCAL_BOT_IDS").split(",")
        resolver = ActorResolver.new(client, local_bot_ids: own,
                                             peer_bot_ids: ENV.fetch("MATTERMOST_PEER_BOT_IDS", "").split(","))
        new(db, client: client, resolver: resolver, channels: ENV.fetch("MATTERMOST_CHANNEL_IDS").split(","))
      end

      def initialize(db, client:, resolver:, channels:)
        @db, @client, @resolver, @channels = db, client, resolver, channels
        @router = Router.new(db)
        @channels.each { |id| @resolver.identifier!(id) }
      end

      def run
        raise "Chat transport live evidence pending; set CHAT_VALIDATION_MODE=1 only for disposable validation" unless ENV["CHAT_VALIDATION_MODE"] == "1"

        delay = 1
        loop do
          begin
            endpoint = Async::HTTP::Endpoint.parse("#{@client.url.sub(/^http/, 'ws')}/api/v4/websocket")
            Async::WebSocket::Client.connect(endpoint) do |socket|
              socket.write(JSON.generate({ seq: 1, action: "authentication_challenge",
                                           data: { token: @client.token } }))
              socket.flush
              auth = Async::Task.current.with_timeout(10) do
                loop do
                  value = JSON.parse(socket.read.to_s)
                  break value if value["seq_reply"] == 1
                end
              end
              raise Client::Error,
                    "WebSocket authentication failed" unless auth["status"] == "OK" && auth["seq_reply"] == 1

              # Connect first, then backfill while events accumulate on socket.
              reconciliation = Reconcile.new(@db, client: @client, resolver: @resolver, router: @router)
              @channels.each { |id| reconciliation.channel(id) }
              delay = 1
              Health.touch("chat-listener")
              loop do
                message = Async::Task.current.with_timeout(30) { socket.read }
                raise EOFError, "WebSocket closed" unless message

                envelope = JSON.parse(message.to_s)
                next unless ActorResolver::KINDS.include?(envelope["event"])

                begin
                  delivery = @resolver.event(envelope)
                  next unless @channels.include?(delivery.channel_id)

                  @router.ingest(delivery: delivery)
                rescue ArgumentError, Client::Error
                  warn "Rejected unverified Mattermost event; REST reconciliation remains required"
                end
                Health.touch("chat-listener")
              end
            end
          rescue Client::Error, IOError, Async::TimeoutError, SystemCallError, JSON::ParserError
            warn "Mattermost listener disconnected; reconnecting with durable backfill"
            Async::Task.current.sleep(delay)
            delay = [delay * 2, 30].min
          end
        end
      end
    end
  end
end

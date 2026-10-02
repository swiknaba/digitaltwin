# frozen_string_literal: true

require "async/http/client"
require "async/http/endpoint"
module Domains
  module Mattermost
    class Client
      class Error < StandardError
        attr_reader :status

        def initialize(message, status: nil)
          @status = status
          super(message)
        end
      end
      attr_reader :url

      def initialize(url:, token_file:)
        parsed = URI(url)
        raise ArgumentError, "Expected HTTP(S) Mattermost base URL" unless %w[http
                                                                              https].include?(parsed.scheme) && parsed.host && !parsed.userinfo && ["",
                                                                                                                                                    "/"].include?(parsed.path) && !parsed.query && !parsed.fragment

        @url = url.delete_suffix("/")
        @token_file = token_file
      end

      def token
        value = File.read(@token_file).strip
        raise Error, "Missing Mattermost credential" if value.empty?

        value
      end

      def get(path) = request("GET", path)
      def post(path, body) = request("POST", path, body)

      def request(method, path, body = nil)
        raise ArgumentError, "Expected API4 path" unless path.start_with?("/api/v4/") && !path.include?("\n")

        task = Async::Task.current
        task.with_timeout(10) do
          # Owned by this call/reactor. Always close response and client; no
          # cross-reactor global connection cache and no DB transaction here.
          endpoint = Async::HTTP::Endpoint.parse(@url, timeout: 5)
          client = Async::HTTP::Client.new(endpoint, retries: 1)
          headers = { "authorization" => "Bearer #{token}", "content-type" => "application/json" }
          response = client.call(Protocol::HTTP::Request[method, path, headers, body && JSON.generate(body)])
          data = +""
          response.body&.each do |chunk|
            data << chunk
            raise Error, "Mattermost response too large" if data.bytesize > 2_097_152
          end
          raise Error.new("Mattermost HTTP #{response.status}", status: response.status) unless (200..299).cover?(response.status)

          JSON.parse(data)
        ensure
          response&.close
          client&.close
        end
      end
    end
  end
end

# typed: strict
# frozen_string_literal: true

require "async/http/client"
require "async/http/endpoint"
require "json"
require "uri"

module Domains
  module Mattermost
    class Client
      extend T::Sig

      JsonObject = T.type_alias { T::Hash[String, Object] }

      class Error < StandardError
        extend T::Sig

        sig { returns(T.nilable(Integer)) }
        attr_reader :status

        sig { params(message: String, status: T.nilable(Integer)).void }
        def initialize(message, status: nil)
          @status = status
          super(message)
        end
      end

      class HttpResponse < T::Struct
        const :status, Integer
        const :body, String
      end

      MAX_RESPONSE_BYTES = T.let(2_097_152, Integer)

      sig { returns(String) }
      attr_reader :url

      sig { params(url: String, token_file: String).void }
      def initialize(url:, token_file:)
        parsed = URI(url)
        unless %w[http https].include?(parsed.scheme) && parsed.host && !parsed.userinfo && ["", "/"].include?(parsed.path) && !parsed.query && !parsed.fragment
          raise ArgumentError, "Expected HTTP(S) Mattermost base URL"
        end

        @url = T.let(url.delete_suffix("/"), String)
        @token_file = T.let(token_file, String)
      end

      sig { returns(String) }
      def token
        value = File.read(@token_file).strip
        raise Error, "Missing Mattermost credential" if value.empty?

        value
      end

      sig { params(path: String).returns(JsonObject) }
      def get(path)
        request("GET", path)
      end

      sig { params(path: String, body: JsonObject).returns(JsonObject) }
      def post(path, body)
        request("POST", path, body)
      end

      sig { params(method: String, path: String, body: T.nilable(JsonObject)).returns(JsonObject) }
      def request(method, path, body = nil)
        validate_path!(path)
        response = perform_request(method: method, path: path, body: body)
        raise Error.new("Mattermost HTTP #{response.status}", status: response.status) unless (200..299).cover?(response.status)

        json_object(JSON.parse(response.body))
      rescue JSON::ParserError
        raise Error, "Malformed Mattermost JSON response"
      end

      private

      sig { params(path: String).void }
      def validate_path!(path)
        raise ArgumentError, "Expected API4 path" unless path.start_with?("/api/v4/") && !path.include?("\n")
      end

      sig { params(method: String, path: String, body: T.nilable(JsonObject)).returns(HttpResponse) }
      def perform_request(method:, path:, body:)
        client = T.let(nil, T.nilable(Async::HTTP::Client))
        response = T.let(nil, T.nilable(Protocol::HTTP::Response))
        request_body = body.nil? ? nil : JSON.generate(body)

        Async::Task.current.with_timeout(10) do
          endpoint = Async::HTTP::Endpoint.parse(@url, timeout: 5)
          client = Async::HTTP::Client.new(endpoint, retries: 1)
          headers = { "authorization" => "Bearer #{token}", "content-type" => "application/json" }
          response = client.call(Protocol::HTTP::Request[method, path, headers, request_body])
          HttpResponse.new(status: response.status, body: response_body(response))
        end
      ensure
        response&.close
        client&.close
      end

      sig { params(response: Protocol::HTTP::Response).returns(String) }
      def response_body(response)
        body = +""
        response.body&.each do |chunk|
          body << chunk
          raise Error, "Mattermost response too large" if body.bytesize > MAX_RESPONSE_BYTES
        end
        body
      end

      sig { params(value: Object).returns(JsonObject) }
      def json_object(value)
        raise Error, "Malformed Mattermost JSON response" unless value.is_a?(Hash)

        object = T.let({}, JsonObject)
        value.each do |key, item|
          raise Error, "Malformed Mattermost JSON response" unless key.is_a?(String) && json_value?(item)

          object[key] = item
        end
        object
      end

      sig { params(value: Object).returns(T::Boolean) }
      def json_value?(value)
        case value
        when String, Integer, Float, TrueClass, FalseClass, NilClass
          true
        when Array
          value.all? { |item| json_value?(item) }
        when Hash
          value.all? { |key, item| key.is_a?(String) && json_value?(item) }
        else
          false
        end
      end
    end
  end
end

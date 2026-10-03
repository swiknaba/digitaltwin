# typed: strict
# frozen_string_literal: true

module Adapters
  module Mcp
    # Standalone HTTP tool gateway for the stdio server; bin/mcp loads it by
    # path, and the Runtime image installs it as http_tools.rb.
    class HttpTools
      extend T::Sig
      include Server::ToolGateway

      JsonObject = T.type_alias { T::Hash[String, Object] }

      sig { params(url: String).void }
      def initialize(url:)
        @base = T.let(URI(url), URI::Generic)
        raise ArgumentError, "Expected private HTTP(S) base URL" unless %w[http https].include?(@base.scheme) && @base.host && !@base.userinfo && ["", "/"].include?(@base.path) && !@base.query && !@base.fragment
      end

      sig { override.returns(T::Array[JsonObject]) }
      def definitions
        value = request("GET", "/internal/master/manifest").fetch("tools")
        raise ArgumentError, "Invalid tool manifest" unless value.is_a?(Array) && value.all? { |item| json_object?(item) }

        value
      end

      sig { override.params(name: String, args: JsonObject, token: String).returns(Object) }
      def call(name, args, token:)
        request("POST", "/internal/master/tools", { "name" => name, "arguments" => args }, token).fetch("result")
      end

      sig { params(method: String, path: String, body: T.nilable(JsonObject), token: T.nilable(String)).returns(JsonObject) }
      private def request(method, path, body = nil, token = nil)
        target = URI.join(@base.to_s, path)
        headers = { "Content-Type" => "application/json" }
        headers["Authorization"] = "Bearer #{token}" if token
        request = (method == "GET" ? Net::HTTP::Get : Net::HTTP::Post).new(target, headers)
        request.body = JSON.generate(body) if body
        response = Net::HTTP.start(target.host, target.port, use_ssl: target.scheme == "https", open_timeout: 5, read_timeout: 10, write_timeout: 10) { |http| http.request(request) }
        raise IOError, "Tool request rejected or uncertain" unless response.code == "200" && response.body.bytesize <= 1_048_576

        parsed = JSON.parse(response.body)
        raise ArgumentError, "Tool response is not an object" unless json_object?(parsed)

        parsed
      rescue JSON::ParserError
        raise ArgumentError, "Tool response is invalid JSON"
      end

      sig { params(value: Object).returns(T::Boolean) }
      private def json_object?(value)
        value.is_a?(Hash) && value.keys.all? { |key| key.is_a?(String) }
      end
    end
  end
end

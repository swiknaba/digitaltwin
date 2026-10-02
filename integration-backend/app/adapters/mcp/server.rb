# typed: strict
# frozen_string_literal: true

module Adapters
  module Mcp
    # Standalone stdio JSON-RPC MCP server. bin/mcp loads this file by path
    # without Zeitwerk, and the Runtime image installs it as mcp.rb.
    class Server
      extend T::Sig

      JsonObject = T.type_alias { T::Hash[String, Object] }

      module ToolGateway
        extend T::Helpers
        extend T::Sig

        interface!

        sig { abstract.returns(T::Array[Object]) }
        def definitions; end

        sig { abstract.params(name: String, args: JsonObject, token: String).returns(Object) }
        def call(name, args, token:); end
      end

      Stream = T.type_alias { T.any(IO, StringIO) }

      sig { params(tools: ToolGateway, token_file: String).void }
      def initialize(tools:, token_file:)
        @tools = tools
        @token_file = token_file
      end

      sig { params(input: Stream, output: Stream).void }
      def serve(input: $stdin, output: $stdout)
        while (line = input.gets("\n", 65_537))
          raise ArgumentError, "MCP request too large" if line.bytesize > 65_536

          begin
            request = JSON.parse(line)
            raise JSON::ParserError unless json_object?(request)
          rescue JSON::ParserError
            output.puts(JSON.generate(jsonrpc: "2.0", id: nil, error: { code: -32700, message: "Invalid JSON-RPC frame" }))
            output.flush
            next
          end
          next unless request.key?("id")

          id = request["id"]
          begin
            raise ArgumentError, "Expected JSON-RPC 2.0" unless request["jsonrpc"] == "2.0"

            result = case request["method"]
                     when "initialize"
                       { "protocolVersion" => "2024-11-05", "capabilities" => { "tools" => {} }, "serverInfo" => { "name" => "digitaltwin", "version" => "1" } }
                     when "ping" then {}
                     when "tools/list" then { "tools" => @tools.definitions }
                     when "tools/call"
                       params = tool_params(request.fetch("params"))
                       value = @tools.call(string_value(params, "name"), arguments(params.fetch("arguments")), token: File.read(@token_file).strip)
                       { "content" => [{ "type" => "text", "text" => JSON.generate(value) }] }
                     else raise ArgumentError, "Unsupported MCP method"
                     end
            output.puts(JSON.generate(jsonrpc: "2.0", id: id, result: result))
          rescue StandardError
            output.puts(JSON.generate(jsonrpc: "2.0", id: id, error: { code: -32602, message: "Request rejected; verify source, capability, fields and workflow state" }))
          end
          output.flush
        end
      end

      sig { params(value: Object).returns(T::Boolean) }
      private def json_object?(value)
        value.is_a?(Hash) && value.keys.all? { |key| key.is_a?(String) }
      end

      sig { params(value: Object).returns(JsonObject) }
      private def tool_params(value)
        object_value(value, "Tool parameters must be an object")
      end

      sig { params(value: Object).returns(JsonObject) }
      private def arguments(value)
        object_value(value, "Tool arguments must be an object")
      end

      sig { params(value: Object, message: String).returns(JsonObject) }
      private def object_value(value, message)
        raise ArgumentError, message unless value.is_a?(Hash)

        object = T.let({}, JsonObject)
        value.each do |key, item|
          raise ArgumentError, message unless key.is_a?(String)

          object[key] = item
        end
        object
      end

      sig { params(object: JsonObject, key: String).returns(String) }
      private def string_value(object, key)
        value = object.fetch(key)
        raise ArgumentError, "Expected string tool parameter" unless value.is_a?(String)

        value
      end
    end
  end
end

# frozen_string_literal: true

require "json"
module Domains
  module Controller
    class Mcp
      def initialize(tools:, token_file:)
        @tools, @token_file = tools, token_file
      end

      def serve(input: $stdin, output: $stdout)
        while (line = input.gets("\n", 65_537))
          raise ArgumentError, "MCP request too large" if line.bytesize > 65_536

          begin
            request = JSON.parse(line)
            raise JSON::ParserError unless request.is_a?(Hash)
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
                       p = request.fetch("params")
                       value = @tools.call(p.fetch("name"), p.fetch("arguments"), token: File.read(@token_file).strip)
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
    end
  end
end

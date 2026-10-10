# typed: strict
# frozen_string_literal: true

module Adapters
  module Mcp
    # Presents only the fixed usage gateway through the same stdio JSON-RPC
    # transport used by the existing Commander MCP bridge.
    class AgentsviewUsageServer
      extend T::Sig

      Stream = T.type_alias { T.any(IO, StringIO) }

      sig { params(command: AgentsviewUsageCommand, token_file: String).void }
      def initialize(command:, token_file:)
        @server = T.let(Server.new(tools: command, token_file: token_file), Server)
      end

      sig { params(input: Stream, output: Stream).void }
      def serve(input: $stdin, output: $stdout)
        @server.serve(input: input, output: output)
      end
    end
  end
end

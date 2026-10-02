# frozen_string_literal: true

require "json"
require "securerandom"
require "socket"
require "timeout"
module Domains
  module Sessions
    # Captured v0.9.3/protocol22 wire contract. No start or resume operation:
    # prompting targets the persisted pane and keeps the LLM conversation.
    class Herdr
      def initialize(socket_path: "/run/herdr/herdr.sock") = @path = socket_path
      def get(pane) = request("agent.get", { "target" => pane }, "agent_info", pane)
      def prompt(pane, text) = request("agent.prompt", { "target" => pane, "text" => text }, "agent_prompted", pane)

      private def request(method, params, expected, pane)
        Timeout.timeout(5) do
          socket = UNIXSocket.new(@path)
          id = SecureRandom.uuid
          socket.write(JSON.generate(id: id, method: method, params: params) + "\n")
          line = socket.gets("\n", 1_048_577)
          raise IOError, "Invalid Herdr response" unless line && line.end_with?("\n") && line.bytesize <= 1_048_576

          response = JSON.parse(line)
          raise IOError, "Herdr rejected operation" if response["id"] == id && response.key?("error")

          result = response.fetch("result")
          agent = result.fetch("agent")
          raise IOError, "Herdr identity mismatch" unless response["id"] == id && result["type"] == expected && agent["pane_id"] == pane
          raise IOError, "Herdr status invalid" unless %w[idle working blocked done unknown].include?(agent["agent_status"])

          agent
        ensure
          socket&.close
        end
      end
    end
  end
end

# frozen_string_literal: true

require "json"
require "securerandom"
require "socket"
require "timeout"
module Domains
  module Sessions
    class Herdr
      def initialize(socket_path: "/run/herdr/herdr.sock") = @path = socket_path
      def get(pane) = agent("agent.get", { "target" => pane }, "agent_info", pane)
      def prompt(pane, text) = agent("agent.prompt", { "target" => pane, "text" => text }, "agent_prompted", pane)

      def start(pane, name, configuration)
        agent("agent.start", { "pane_id" => pane, "name" => name, "kind" => configuration.fetch("cli"), "args" => configuration.fetch("launch_args") }, "agent_started", pane)
      end

      def workspace(cwd:, label:, env:)
        result = request("workspace.create", { "cwd" => cwd, "label" => label, "env" => env, "focus" => false }, "workspace_created")
        raise IOError, "Missing workspace identity" unless result.dig("workspace", "workspace_id").is_a?(String) && result.dig("root_pane", "pane_id").is_a?(String)

        result
      end

      def close(pane) = request("pane.close", { "pane_id" => pane }, "ok")

      private def agent(method, params, expected, pane)
        value = request(method, params, expected).fetch("agent")
        raise IOError, "Herdr identity mismatch" unless value["pane_id"] == pane
        raise IOError, "Herdr status invalid" unless %w[idle working blocked done unknown].include?(value["agent_status"])

        value
      end
      private def request(method, params, expected)
        Timeout.timeout(5) do
          socket = UNIXSocket.new(@path)
          id = SecureRandom.uuid
          socket.write(JSON.generate(id: id, method: method, params: params) + "\n")
          line = socket.gets("\n", 1_048_577)
          raise IOError, "Invalid Herdr response" unless line && line.end_with?("\n") && line.bytesize <= 1_048_576

          response = JSON.parse(line)
          raise IOError, "Herdr correlation mismatch" unless response["id"] == id
          raise IOError, "Herdr rejected operation" if response.key?("error")

          result = response.fetch("result")
          raise IOError, "Herdr result mismatch" unless result["type"] == expected

          result
        ensure
          socket&.close
        end
      end
    end
  end
end

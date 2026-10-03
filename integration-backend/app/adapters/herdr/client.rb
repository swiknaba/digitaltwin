# typed: strict
# frozen_string_literal: true

module Adapters
  module Herdr
    # JSON-lines client for the local Herdr socket. Every response is checked
    # for correlation, result type, and target pane, then translated into DTOs.
    # Values outside the captured schema raise Errors::ProtocolViolation.
    class Client
      extend T::Sig

      # JSON is an untyped transport boundary. Values remain Object until the
      # field-specific readers below prove their required shape.
      JsonValue = T.type_alias { Object }
      JsonObject = T.type_alias { T::Hash[String, JsonValue] }

      MAX_LINE_BYTES = 1_048_576

      sig { params(socket_path: String).void }
      def initialize(socket_path: "/run/herdr/herdr.sock")
        @path = socket_path
      end

      sig { params(id: String).returns(Dto::Pane) }
      def pane(id)
        agent("agent.get", { "target" => id }, "agent_info", id)
      end

      sig { params(pane_id: String, text: String).void }
      def prompt(pane_id:, text:)
        agent("agent.prompt", { "target" => pane_id, "text" => text }, "agent_prompted", pane_id)
      end

      sig { params(pane_id: String, name: String, launch: Dto::LaunchSpec).returns(Dto::Pane) }
      def start(pane_id:, name:, launch:)
        agent("agent.start", { "pane_id" => pane_id, "name" => name, "kind" => launch.cli, "args" => launch.launch_args }, "agent_started", pane_id)
      end

      sig { params(cwd: T.nilable(String), label: String, env: T::Hash[String, String]).returns(Dto::Workspace) }
      def create_workspace(cwd:, label:, env:)
        result = request("workspace.create", { "cwd" => cwd, "label" => label, "env" => env, "focus" => false }, "workspace_created")
        Dto::Workspace.new(workspace_id: string_field!(object_field!(result, "workspace"), "workspace_id"),
                           root_pane_id: string_field!(object_field!(result, "root_pane"), "pane_id"))
      end

      sig { returns(T::Array[Dto::PaneSummary]) }
      def panes
        object_array_field!(request("pane.list", {}, "pane_list"), "panes").map do |pane|
          Dto::PaneSummary.new(pane_id: string_field!(pane, "pane_id"))
        end
      end

      sig { params(pane_id: String).void }
      def close(pane_id:)
        request("pane.close", { "pane_id" => pane_id }, "ok")
      end

      sig { params(operation: String, params: JsonObject, expected: String, pane_id: String).returns(Dto::Pane) }
      private def agent(operation, params, expected, pane_id)
        value = object_field!(request(operation, params, expected), "agent")
        raise Errors::ProtocolViolation, "Herdr identity mismatch" unless string_field!(value, "pane_id") == pane_id

        Dto::Pane.new(pane_id: pane_id, name: optional_string_field!(value, "name"), cwd: optional_string_field!(value, "cwd"),
                      agent: optional_string_field!(value, "agent"), agent_status: agent_status!(value),
                      agent_session: agent_session!(value), interactive_ready: optional_boolean_field!(value, "interactive_ready"),
                      launch_pending: optional_boolean_field!(value, "launch_pending"))
      end

      sig { params(object: JsonObject).returns(Dto::AgentStatus) }
      private def agent_status!(object)
        status = Dto::AgentStatus.try_deserialize(string_field!(object, "agent_status"))
        raise Errors::ProtocolViolation, "Herdr status invalid" unless status

        status
      end

      sig { params(object: JsonObject).returns(T.nilable(Dto::AgentSession)) }
      private def agent_session!(object)
        return nil if object["agent_session"].nil?

        session = object_field!(object, "agent_session")
        Dto::AgentSession.new(source: string_field!(session, "source"), agent: string_field!(session, "agent"),
                              kind: string_field!(session, "kind"), value: string_field!(session, "value"))
      end

      sig { params(operation: String, params: JsonObject, expected: String).returns(JsonObject) }
      private def request(operation, params, expected)
        socket = T.let(nil, T.nilable(UNIXSocket))
        Timeout.timeout(5) do
          socket = UNIXSocket.new(@path)
          correlation_id = SecureRandom.uuid
          socket.write(JSON.generate(id: correlation_id, method: operation, params: params) + "\n")
          line = socket.gets("\n", MAX_LINE_BYTES + 1)
          raise Errors::ProtocolViolation, "Invalid Herdr response" unless line&.end_with?("\n") && line.bytesize <= MAX_LINE_BYTES

          response = response_from(line)
          raise Errors::ProtocolViolation, "Herdr correlation mismatch" unless response.id == correlation_id
          raise Errors::ProtocolViolation, "Herdr result mismatch" unless response.result_type == expected

          response.payload
        ensure
          socket&.close
        end
      end

      sig { params(line: String).returns(Response) }
      private def response_from(line)
        response = json_object!(JSON.parse(line))
        raise Errors::ProtocolViolation, "Herdr rejected operation" if response.key?("error")

        result = object_field!(response, "result")
        Response.new(id: string_field!(response, "id"), result_type: string_field!(result, "type"), payload: result)
      rescue JSON::ParserError
        raise Errors::ProtocolViolation, "Invalid Herdr response"
      end

      sig { params(value: JsonValue).returns(JsonObject) }
      private def json_object!(value)
        raise Errors::ProtocolViolation, "Invalid Herdr response" unless value.is_a?(Hash)

        object = T.let({}, JsonObject)
        value.each do |key, child|
          raise Errors::ProtocolViolation, "Invalid Herdr response" unless key.is_a?(String)

          object[key] = json_value!(child)
        end
        object
      end

      sig { params(value: JsonValue).returns(JsonValue) }
      private def json_value!(value)
        case value
        when String, Integer, Float, TrueClass, FalseClass, NilClass
          value
        when Array
          value.map { |child| json_value!(child) }
        when Hash
          json_object!(value)
        else
          raise Errors::ProtocolViolation, "Invalid Herdr response"
        end
      end

      sig { params(object: JsonObject, key: String).returns(String) }
      private def string_field!(object, key)
        value = object.fetch(key) { raise Errors::ProtocolViolation, "Invalid Herdr response" }
        raise Errors::ProtocolViolation, "Invalid Herdr response" unless value.is_a?(String)

        value
      end

      sig { params(object: JsonObject, key: String).returns(T.nilable(String)) }
      private def optional_string_field!(object, key)
        value = object[key]
        raise Errors::ProtocolViolation, "Invalid Herdr response" unless value.nil? || value.is_a?(String)

        value
      end

      sig { params(object: JsonObject, key: String).returns(T.nilable(T::Boolean)) }
      private def optional_boolean_field!(object, key)
        value = object[key]
        raise Errors::ProtocolViolation, "Invalid Herdr response" unless value.nil? || value == true || value == false

        value
      end

      sig { params(object: JsonObject, key: String).returns(JsonObject) }
      private def object_field!(object, key)
        json_object!(object.fetch(key) { raise Errors::ProtocolViolation, "Invalid Herdr response" })
      end

      sig { params(object: JsonObject, key: String).returns(T::Array[JsonObject]) }
      private def object_array_field!(object, key)
        value = object.fetch(key) { raise Errors::ProtocolViolation, "Invalid Herdr response" }
        raise Errors::ProtocolViolation, "Invalid Herdr response" unless value.is_a?(Array)

        value.map { |entry| json_object!(entry) }
      end
    end
  end
end

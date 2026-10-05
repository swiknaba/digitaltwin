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
      REQUEST_TIMEOUT_SECONDS = 5.0
      STARTUP_TIMEOUT_SECONDS = 30
      SAFE_ERROR_CODES = T.let(["agent_pane_busy"].freeze, T::Array[String])

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
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + STARTUP_TIMEOUT_SECONDS
        result = begin
          startup_request("agent.start", { "pane_id" => pane_id, "name" => name, "kind" => launch.cli, "args" => launch.launch_args }, "agent_started", deadline: deadline)
        rescue Errors::ProtocolViolation => error
          raise unless error.code == "agent_pane_busy"

          retry_initial_shell_start(pane_id: pane_id, name: name, launch: launch, deadline: deadline, error: error)
        end
        await_start(value: object_field!(result, "agent"), pane_id: pane_id, name: name, kind: launch.cli, deadline: deadline)
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
        pane_from(value: object_field!(request(operation, params, expected), "agent"), pane_id: pane_id)
      end

      sig { params(value: JsonObject, pane_id: String).returns(Dto::Pane) }
      private def pane_from(value:, pane_id:)
        raise Errors::ProtocolViolation, "Herdr identity mismatch" unless string_field!(value, "pane_id") == pane_id

        Dto::Pane.new(pane_id: pane_id, name: optional_string_field!(value, "name"), cwd: optional_string_field!(value, "cwd"),
                      agent: optional_string_field!(value, "agent"), agent_status: agent_status!(value),
                      agent_session: agent_session!(value), interactive_ready: optional_boolean_field!(value, "interactive_ready"),
                      launch_pending: optional_boolean_field!(value, "launch_pending"))
      end

      sig { params(pane: Dto::Pane).returns(T::Boolean) }
      private def initial_shell?(pane)
        pane.agent_status == Dto::AgentStatus::Unknown && pane.name.nil? && pane.agent.nil? && pane.agent_session.nil? && pane.interactive_ready.nil? && pane.launch_pending.nil?
      end

      # Herdr explicitly rejects agent_pane_busy before it starts an agent. One
      # retry is safe only after a correlated read proves that exact pane is
      # still the untouched shell. An opaque/redacted start error never enters
      # this path, and the original deadline covers every observation.
      sig do
        params(pane_id: String, name: String, launch: Dto::LaunchSpec, deadline: T.any(Float, Integer), error: Errors::ProtocolViolation).returns(JsonObject)
      end
      private def retry_initial_shell_start(pane_id:, name:, launch:, deadline:, error:)
        loop do
          raise error if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

          begin
            raise error unless initial_shell?(pane(pane_id))
          rescue Errors::ProtocolViolation => read_error
            raise error unless read_error.code == "unknown"
            raise error if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

            sleep(0.1)
            next
          end
          raise error if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

          return startup_request("agent.start", { "pane_id" => pane_id, "name" => name, "kind" => launch.cli, "args" => launch.launch_args }, "agent_started", deadline: deadline)
        end
      end

      # Socket agent.start acknowledges submission; the pinned CLI additionally
      # waits for a detected, interactive conversation in the same terminal.
      # Poll only the accepted launch. Never repeat its start effect on failure.
      sig { params(value: JsonObject, pane_id: String, name: String, kind: String, deadline: T.any(Float, Integer)).returns(Dto::Pane) }
      private def await_start(value:, pane_id:, name:, kind:, deadline:)
        terminal_id = string_field!(value, "terminal_id")
        loop do
          raise Errors::ProtocolViolation, "Herdr startup terminal replaced" unless string_field!(value, "terminal_id") == terminal_id

          live = pane_from(value: value, pane_id: pane_id)
          raise Errors::ProtocolViolation, "Herdr startup name replaced" unless live.name == name
          raise Errors::ProtocolViolation, "Herdr startup kind mismatch" if live.agent && live.agent != kind
          raise Errors::ProtocolViolation, "Herdr startup blocked" if live.agent_status == Dto::AgentStatus::Blocked

          settled = live.agent_status == Dto::AgentStatus::Idle || live.agent_status == Dto::AgentStatus::Done
          identity = live.agent_session
          if settled && live.interactive_ready == true && live.launch_pending != true && identity && ConversationIdentity.proven?(identity)
            raise Errors::ProtocolViolation, "Herdr conversation agent mismatch" unless identity.agent == kind

            return live
          end
          if settled && live.launch_pending != true && live.interactive_ready != true
            raise Errors::ProtocolViolation, "Herdr startup exited before interactive readiness"
          end
          raise Errors::ProtocolViolation, "Herdr startup readiness timed out" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

          sleep(0.1)
          begin
            value = object_field!(startup_request("agent.get", { "target" => pane_id }, "agent_info", deadline: deadline), "agent")
          rescue Errors::ProtocolViolation => error
            # Herdr can redact a transient read rejection to "unknown" while
            # the accepted launch registers its terminal. Retrying this read
            # cannot repeat the already accepted start effect.
            raise unless error.code == "unknown"
            raise Errors::ProtocolViolation, "Herdr startup readiness timed out" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
          end
        end
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

      # Startup reconciliation has one deadline across its side effect and all
      # observations. Generic calls keep the normal socket timeout.
      sig { params(operation: String, params: JsonObject, expected: String, deadline: T.any(Float, Integer)).returns(JsonObject) }
      private def startup_request(operation, params, expected, deadline:)
        remaining = deadline.to_f - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        raise Errors::ProtocolViolation, "Herdr startup readiness timed out" unless remaining.positive?

        request(operation, params, expected, timeout_seconds: [remaining, REQUEST_TIMEOUT_SECONDS].min)
      end

      sig { params(operation: String, params: JsonObject, expected: String, timeout_seconds: T.nilable(Float)).returns(JsonObject) }
      private def request(operation, params, expected, timeout_seconds: nil)
        socket = T.let(nil, T.nilable(UNIXSocket))
        Timeout.timeout(timeout_seconds || REQUEST_TIMEOUT_SECONDS) do
          socket = UNIXSocket.new(@path)
          correlation_id = SecureRandom.uuid
          socket.write(JSON.generate(id: correlation_id, method: operation, params: params) + "\n")
          line = socket.gets("\n", MAX_LINE_BYTES + 1)
          raise Errors::ProtocolViolation, "Invalid Herdr response" unless line&.end_with?("\n") && line.bytesize <= MAX_LINE_BYTES

          response = response_from(line, correlation_id)
          raise Errors::ProtocolViolation, "Herdr result mismatch" unless response.result_type == expected

          response.payload
        ensure
          socket&.close
        end
      end

      sig { params(line: String, correlation_id: String).returns(Response) }
      private def response_from(line, correlation_id)
        response = json_object!(JSON.parse(line))
        id = string_field!(response, "id")
        raise Errors::ProtocolViolation, "Herdr correlation mismatch" unless id == correlation_id

        if response.key?("error")
          error = object_field!(response, "error")
          code = safe_error_code(error)
          raise Errors::ProtocolViolation.new("Herdr rejected operation: #{code}", code: code)
        end

        result = object_field!(response, "result")
        Response.new(id: id, result_type: string_field!(result, "type"), payload: result)
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

      sig { params(error: JsonObject).returns(String) }
      private def safe_error_code(error)
        code = string_field!(error, "code")
        SAFE_ERROR_CODES.include?(code) ? code : "unknown"
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

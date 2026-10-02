# typed: strict
# frozen_string_literal: true

require "json"
require "securerandom"
require "socket"
require "timeout"

module Domains
  module Sessions
    class Herdr
      extend T::Sig

      # JSON is an untyped transport boundary. Values remain Object until the
      # field-specific validators below prove their required shape.
      JsonValue = T.type_alias { Object }
      JsonObject = T.type_alias { T::Hash[String, JsonValue] }

      class Response < T::Struct
        const :id, String
        const :result_type, String
        const :payload, JsonObject
      end

      sig { params(socket_path: String).void }
      def initialize(socket_path: "/run/herdr/herdr.sock")
        @path = socket_path
      end

      sig { params(pane: String).returns(JsonObject) }
      def get(pane)
        agent("agent.get", { "target" => pane }, "agent_info", pane)
      end

      sig { params(pane: String, text: String).returns(JsonObject) }
      def prompt(pane, text)
        agent("agent.prompt", { "target" => pane, "text" => text }, "agent_prompted", pane)
      end

      sig { params(pane: String, name: String, configuration: JsonObject).returns(JsonObject) }
      def start(pane, name, configuration)
        agent("agent.start", { "pane_id" => pane, "name" => name, "kind" => string_field!(configuration, "cli"),
                               "args" => string_array_field!(configuration, "launch_args") }, "agent_started", pane)
      end

      sig { params(cwd: T.nilable(String), label: String, env: T::Hash[String, String]).returns(JsonObject) }
      def workspace(cwd:, label:, env:)
        result = request("workspace.create", { "cwd" => cwd, "label" => label, "env" => env, "focus" => false }, "workspace_created")
        string_field!(object_field!(result, "workspace"), "workspace_id")
        string_field!(object_field!(result, "root_pane"), "pane_id")
        result
      end

      sig { returns(T::Array[JsonObject]) }
      def panes
        result = object_array_field!(request("pane.list", {}, "pane_list"), "panes")
        result.each { |pane| string_field!(pane, "pane_id") }
        result
      end

      sig { params(pane: String).returns(JsonObject) }
      def close(pane)
        request("pane.close", { "pane_id" => pane }, "ok")
      end

      private

      sig { params(operation: String, params: JsonObject, expected: String, pane: String).returns(JsonObject) }
      def agent(operation, params, expected, pane)
        value = object_field!(request(operation, params, expected), "agent")
        raise IOError, "Herdr identity mismatch" unless string_field!(value, "pane_id") == pane

        status = string_field!(value, "agent_status")
        raise IOError, "Herdr status invalid" unless %w[idle working blocked done unknown].include?(status)

        value
      end

      sig { params(operation: String, params: JsonObject, expected: String).returns(JsonObject) }
      def request(operation, params, expected)
        socket = T.let(nil, T.nilable(UNIXSocket))
        Timeout.timeout(5) do
          socket = UNIXSocket.new(@path)
          correlation_id = SecureRandom.uuid
          socket.write(JSON.generate(id: correlation_id, method: operation, params: params) + "\n")
          line = socket.gets("\n", 1_048_577)
          raise IOError, "Invalid Herdr response" unless line&.end_with?("\n") && line.bytesize <= 1_048_576

          response = response_from(line)
          raise IOError, "Herdr correlation mismatch" unless response.id == correlation_id
          raise IOError, "Herdr result mismatch" unless response.result_type == expected

          response.payload
        ensure
          socket&.close
        end
      end

      sig { params(line: String).returns(Response) }
      def response_from(line)
        response = json_object!(JSON.parse(line))
        raise IOError, "Herdr rejected operation" if response.key?("error")

        result = object_field!(response, "result")
        Response.new(id: string_field!(response, "id"), result_type: string_field!(result, "type"), payload: result)
      rescue JSON::ParserError
        raise IOError, "Invalid Herdr response"
      end

      sig { params(value: JsonValue).returns(JsonObject) }
      def json_object!(value)
        raise IOError, "Invalid Herdr response" unless value.is_a?(Hash)

        object = T.let({}, JsonObject)
        value.each do |key, child|
          raise IOError, "Invalid Herdr response" unless key.is_a?(String)

          object[key] = json_value!(child)
        end
        object
      end

      sig { params(value: JsonValue).returns(JsonValue) }
      def json_value!(value)
        case value
        when String, Integer, Float, TrueClass, FalseClass, NilClass
          value
        when Array
          value.map { |child| json_value!(child) }
        when Hash
          json_object!(value)
        else
          raise IOError, "Invalid Herdr response"
        end
      end

      sig { params(object: JsonObject, key: String).returns(String) }
      def string_field!(object, key)
        value = object.fetch(key) { raise IOError, "Invalid Herdr response" }
        raise IOError, "Invalid Herdr response" unless value.is_a?(String)

        value
      end

      sig { params(object: JsonObject, key: String).returns(JsonObject) }
      def object_field!(object, key)
        json_object!(object.fetch(key) { raise IOError, "Invalid Herdr response" })
      end

      sig { params(object: JsonObject, key: String).returns(T::Array[JsonObject]) }
      def object_array_field!(object, key)
        value = object.fetch(key) { raise IOError, "Invalid Herdr response" }
        raise IOError, "Invalid Herdr response" unless value.is_a?(Array)

        value.map { |entry| json_object!(entry) }
      end

      sig { params(object: JsonObject, key: String).returns(T::Array[String]) }
      def string_array_field!(object, key)
        value = object.fetch(key) { raise IOError, "Invalid Herdr configuration" }
        raise IOError, "Invalid Herdr configuration" unless value.is_a?(Array) && value.all? { |entry| entry.is_a?(String) }

        value
      end
    end
  end
end

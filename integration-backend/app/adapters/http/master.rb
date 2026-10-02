# typed: strict
# frozen_string_literal: true

module Adapters
  module Http
    class Master < Base
      Response = T.type_alias { Kirei::Routing::RackResponseType }
      Params = T.type_alias { T::Hash[String, Object] }
      ToolArguments = T.type_alias { T::Hash[String, Object] }

      sig { returns(Response) }
      def manifest
        render_json({ "tools" => manifest_definitions }, status: 200)
      end

      sig { returns(Response) }
      def tools
        values = request_params
        return unexpected_fields_response unless exact_keys?(values, %w[arguments name])

        request_value = tool_request(values)
        db = Kirei::App.raw_db_connection
        services = Domains::Commander::Services.from_env(db)
        requests = Domains::Commander::Requests.new(db, source: services.source)
        value = Domains::Commander::Tools.new(services: services, requests: requests).call(request_value.name, request_value.arguments, token: bearer)
        render_json({ "result" => value }, status: 200)
      rescue ArgumentError, Sequel::Error, Adapters::Mattermost::Errors::RequestFailed
        rejected_response
      end

      sig { returns(Response) }
      def reply
        values = request_params
        return unexpected_fields_response unless exact_keys?(values, %w[request_id text])

        request_value = reply_request(values)
        services = Domains::Commander::Services.from_env(Kirei::App.raw_db_connection)
        master = services.master
        raise ArgumentError, "Master not configured" unless master

        master.reply(request_id: request_value.request_id, token: bearer, text: request_value.text)
        render_json({ "status" => "queued" }, status: 202)
      rescue ArgumentError, Sequel::Error, Adapters::Mattermost::Errors::RequestFailed
        rejected_response
      end

      sig { returns(T::Array[T::Hash[String, Object]]) }
      private def manifest_definitions
        Domains::Commander::Tools::DEFINITIONS.map do |name, fields|
          properties = T.let({}, T::Hash[String, Object])
          fields.each do |field, type|
            properties[field] = type == "array" ? { "type" => "array", "items" => { "type" => "integer" }, "maxItems" => 10 } : { "type" => type }
          end
          properties["request_id"] = { "type" => "string" }
          { "name" => name, "description" => "Verified request-bound #{name.tr("_", " ")}", "inputSchema" => { "type" => "object", "properties" => properties, "required" => properties.keys, "additionalProperties" => false } }
        end
      end

      sig { params(values: Params).returns(Dto::ToolRequest) }
      private def tool_request(values)
        Dto::ToolRequest.new(name: string(values, "name"), arguments: arguments(values.fetch("arguments")))
      end

      sig { params(values: Params).returns(Dto::ReplyRequest) }
      private def reply_request(values)
        Dto::ReplyRequest.new(request_id: string(values, "request_id"), text: string(values, "text"))
      end

      sig { params(values: Params, expected: T::Array[String]).returns(T::Boolean) }
      private def exact_keys?(values, expected)
        values.keys.sort == expected
      end

      sig { returns(Params) }
      private def request_params
        values = T.let({}, Params)
        params.each do |key, value|
          values[key] = value
        end
        values
      end

      sig { params(value: Object).returns(ToolArguments) }
      private def arguments(value)
        raise ArgumentError, "Invalid tool arguments" unless value.is_a?(Hash)

        result = T.let({}, ToolArguments)
        value.each do |key, item|
          raise ArgumentError, "Invalid tool arguments" unless key.is_a?(String)

          result[key] = item
        end
        result
      end

      sig { params(values: Params, key: String).returns(String) }
      private def string(values, key)
        value = values.fetch(key)
        raise ArgumentError, "Invalid request" unless value.is_a?(String)

        value
      end

      sig { returns(String) }
      private def bearer
        value = request.env["HTTP_AUTHORIZATION"]
        raise ArgumentError, "Request authorization required" unless value.is_a?(String) && value.start_with?("Bearer ") && value.length > 7

        value.delete_prefix("Bearer ")
      end

      sig { returns(Response) }
      private def rejected_response
        render_json({ "error" => "Request rejected" }, status: 403)
      end

      sig { returns(Response) }
      private def unexpected_fields_response
        render_json({ "error" => "Unexpected fields" }, status: 400)
      end
    end
  end
end

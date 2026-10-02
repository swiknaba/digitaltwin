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
        token = bearer
        # An unknown tool name raises KeyError, outside the rejected response.
        name = Services::Master::Dto::ToolName.deserialize(request_value.name)
        result = Services::Composition.instance.tools.call(name: name, arguments: tool_arguments(request_value.arguments), token: token)
        return rejected_response if result.failed?

        render_json({ "result" => ToolJson.call(result.result) }, status: 200)
      rescue ArgumentError, Sequel::Error, Adapters::Mattermost::Errors::RequestFailed
        rejected_response
      end

      sig { returns(Response) }
      def reply
        values = request_params
        return unexpected_fields_response unless exact_keys?(values, %w[request_id text])

        request_value = reply_request(values)
        reply = Services::Composition.instance.reply
        raise ArgumentError, "Master not configured" unless reply

        result = reply.call(request_id: request_value.request_id, token: bearer, text: request_value.text)
        return rejected_response if result.failed?

        render_json({ "status" => "queued" }, status: 202)
      rescue ArgumentError, Sequel::Error, Adapters::Mattermost::Errors::RequestFailed
        rejected_response
      end

      sig { returns(T::Array[T::Hash[String, Object]]) }
      private def manifest_definitions
        Services::Master::Dto::ToolName.values.map do |name|
          properties = T.let({}, T::Hash[String, Object])
          name.fields.each do |field|
            type = field.json_type
            properties[field.serialize] = type == "array" ? { "type" => "array", "items" => { "type" => "integer" }, "maxItems" => 10 } : { "type" => type }
          end
          properties["request_id"] = { "type" => "string" }
          tool = name.serialize
          { "name" => tool, "description" => "Verified request-bound #{tool.tr("_", " ")}", "inputSchema" => { "type" => "object", "properties" => properties, "required" => properties.keys, "additionalProperties" => false } }
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

      # A value of the wrong JSON type becomes nil, so Tools rejects it in its
      # own check order.
      sig { params(values: ToolArguments).returns(Services::Master::Dto::ToolArguments) }
      private def tool_arguments(values)
        evidence = values["evidence_inbox_ids"]
        version = values["expected_version"]
        Services::Master::Dto::ToolArguments.new(
          fields: values.keys, request_id: string_or_nil(values["request_id"]), project_id: string_or_nil(values["project_id"]),
          title: string_or_nil(values["title"]), workflow_id: string_or_nil(values["workflow_id"]), action: string_or_nil(values["action"]),
          expected_version: version.is_a?(Integer) ? version : nil,
          evidence_inbox_ids: evidence.is_a?(Array) ? evidence.map { |item| string_or_nil(item) } : nil
        )
      end

      sig { params(value: Object).returns(T.nilable(String)) }
      private def string_or_nil(value) = value.is_a?(String) ? value : nil

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

# typed: strict
# frozen_string_literal: true

module Controllers
  class Master < Base
    extend T::Sig

    Response = T.type_alias { Kirei::Routing::RackResponseType }
    Params = T.type_alias { T::Hash[String, Object] }
    ToolArguments = T.type_alias { T::Hash[String, Object] }

    class ToolRequest < T::Struct
      const :name, String
      const :arguments, ToolArguments
    end

    class ReplyRequest < T::Struct
      const :request_id, String
      const :text, String
    end

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
      services = Domains::Controller::Services.from_env(db)
      requests = Domains::Controller::Requests.new(db, source: services.source)
      value = Domains::Controller::Tools.new(db, services: services, requests: requests).call(request_value.name, request_value.arguments, token: bearer)
      render_json({ "result" => value }, status: 200)
    rescue ArgumentError, Sequel::Error, Domains::Mattermost::Client::Error
      rejected_response
    end

    sig { returns(Response) }
    def reply
      values = request_params
      return unexpected_fields_response unless exact_keys?(values, %w[request_id text])

      request_value = reply_request(values)
      services = Domains::Controller::Services.from_env(Kirei::App.raw_db_connection)
      master = services.master
      raise ArgumentError, "Master not configured" unless master

      master.reply(request_id: request_value.request_id, token: bearer, text: request_value.text)
      render_json({ "status" => "queued" }, status: 202)
    rescue ArgumentError, Sequel::Error, Domains::Mattermost::Client::Error
      rejected_response
    end

    private

    sig { returns(T::Array[T::Hash[String, Object]]) }
    def manifest_definitions
      Domains::Controller::Tools::DEFINITIONS.map do |name, fields|
        properties = T.let({}, T::Hash[String, Object])
        fields.each do |field, type|
          properties[field] = type == "array" ? { "type" => "array", "items" => { "type" => "integer" }, "maxItems" => 10 } : { "type" => type }
        end
        properties["request_id"] = { "type" => "string" }
        { "name" => name, "description" => "Verified request-bound #{name.tr("_", " ")}", "inputSchema" => { "type" => "object", "properties" => properties, "required" => properties.keys, "additionalProperties" => false } }
      end
    end

    sig { params(values: Params).returns(ToolRequest) }
    def tool_request(values)
      ToolRequest.new(name: string(values, "name"), arguments: arguments(values.fetch("arguments")))
    end

    sig { params(values: Params).returns(ReplyRequest) }
    def reply_request(values)
      ReplyRequest.new(request_id: string(values, "request_id"), text: string(values, "text"))
    end

    sig { params(values: Params, expected: T::Array[String]).returns(T::Boolean) }
    def exact_keys?(values, expected)
      values.keys.sort == expected
    end

    sig { returns(Params) }
    def request_params
      values = T.let({}, Params)
      params.each do |key, value|
        values[key] = value
      end
      values
    end

    sig { params(value: Object).returns(ToolArguments) }
    def arguments(value)
      raise ArgumentError, "Invalid tool arguments" unless value.is_a?(Hash)

      result = T.let({}, ToolArguments)
      value.each do |key, item|
        raise ArgumentError, "Invalid tool arguments" unless key.is_a?(String)

        result[key] = item
      end
      result
    end

    sig { params(values: Params, key: String).returns(String) }
    def string(values, key)
      value = values.fetch(key)
      raise ArgumentError, "Invalid request" unless value.is_a?(String)

      value
    end

    sig { returns(String) }
    def bearer
      value = request.env["HTTP_AUTHORIZATION"]
      raise ArgumentError, "Request authorization required" unless value.is_a?(String) && value.start_with?("Bearer ") && value.length > 7

      value.delete_prefix("Bearer ")
    end

    sig { returns(Response) }
    def rejected_response
      render_json({ "error" => "Request rejected" }, status: 403)
    end

    sig { returns(Response) }
    def unexpected_fields_response
      render_json({ "error" => "Unexpected fields" }, status: 400)
    end
  end
end

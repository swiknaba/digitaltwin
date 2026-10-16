# typed: strict
# frozen_string_literal: true

require "digest"
require "json"
require "net/http"
require "uri"

module Adapters
  module OpenCode
    # Uses an operator-owned, already authenticated OpenCode session. The
    # authorization value never enters the agent/MCP payload or persistence.
    class ConfiguredGateway
      extend T::Sig

      include Gateway

      sig { params(base_url: String, session_id: String, authorization: String).void }
      def initialize(base_url:, session_id:, authorization:)
        @base_url = T.let(URI(base_url), URI::Generic)
        @session_id = T.let(session_id, String)
        @authorization = T.let(authorization, String)
      end

      sig { override.params(task_id: String, text: String, references: T::Array[String], due_at: Time, timezone: String, origin: String, attempt: Integer, delivery_key: String).returns(Domains::FutureTasks::Dto::DeliveryReceipt) }
      def deliver(task_id:, text:, references:, due_at:, timezone:, origin:, attempt:, delivery_key:)
        input_id = input_id_for("delivery", delivery_key)
        prompt(input_id:, text: delivery_text(task_id:, text:, references:, due_at:, timezone:, origin:, attempt:, delivery_key:))
        Domains::FutureTasks::Dto::DeliveryReceipt.new(delivery_key:, commander_item_id: input_id)
      end

      sig { override.params(delivery_key: String).returns(Domains::FutureTasks::Dto::BridgeResolution) }
      def reconcile(delivery_key:)
        input_id = input_id_for("delivery", delivery_key)
        response = request("GET", "/api/session/#{escaped(@session_id)}/message/#{escaped(input_id)}", nil)
        return Domains::FutureTasks::Dto::BridgeResolution.new if response.code.to_i == 404

        raise "OpenCode rejected reconciliation (HTTP #{response.code})" unless response.code.to_i.between?(200, 299)

        Domains::FutureTasks::Dto::BridgeResolution.new(receipt: Domains::FutureTasks::Dto::DeliveryReceipt.new(delivery_key:, commander_item_id: input_id))
      end

      sig { override.params(delivery_key: String, outcome: String).void }
      def record_outcome(delivery_key:, outcome:)
        prompt(input_id: input_id_for("outcome", "#{delivery_key}\n#{outcome}"), text: "Future task #{delivery_key} was resolved as #{outcome}.")
      end

      sig { params(input_id: String, text: String).void }
      private def prompt(input_id:, text:)
        response = request("POST", "/api/session/#{escaped(@session_id)}/prompt", { "id" => input_id, "text" => text, "metadata" => { "fromCommander" => true }, "resume" => true })
        raise "OpenCode rejected future-task input (HTTP #{response.code})" unless response.code.to_i.between?(200, 299)
      end

      sig { params(task_id: String, text: String, references: T::Array[String], due_at: Time, timezone: String, origin: String, attempt: Integer, delivery_key: String).returns(String) }
      private def delivery_text(task_id:, text:, references:, due_at:, timezone:, origin:, attempt:, delivery_key:)
        reference_text = references.empty? ? "none" : references.join(", ")
        "Commander-directed scheduled check-in:\n#{text}\n\nTask: #{task_id}\nDue: #{due_at.utc.iso8601} (#{timezone})\nOrigin: #{origin}\nAttempt: #{attempt}\nReferences: #{reference_text}\nDelivery key: #{delivery_key}"
      end

      sig { params(kind: String, value: String).returns(String) }
      private def input_id_for(kind, value)
        "msg_future_task_#{kind}_#{Digest::SHA256.hexdigest(value)}"
      end

      sig { params(method: String, path: String, body: T.nilable(T::Hash[String, T.any(T::Boolean, String, T::Array[String], T::Hash[String, T::Boolean])])).returns(Net::HTTPResponse) }
      private def request(method, path, body)
        target = @base_url + path
        request = Net::HTTP.const_get(method.capitalize).new(target, { "Authorization" => @authorization, "Content-Type" => "application/json" })
        request.body = JSON.generate(body) if body
        Net::HTTP.start(target.host, target.port, use_ssl: target.scheme == "https", open_timeout: 2, read_timeout: 5) { |client| client.request(request) }
      end

      sig { params(value: String).returns(String) }
      private def escaped(value)
        URI.encode_uri_component(value)
      end
    end
  end
end

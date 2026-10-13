# typed: strict
# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Adapters
  module CommanderBridge
    # Operator-configured private bridge client. Its identity is read from a
    # mounted file; neither agents nor project configuration receive it.
    class ConfiguredGateway
      extend T::Sig

      include Gateway

      sig { params(base_url: String, identity: String).void }
      def initialize(base_url:, identity:)
        @base_url = T.let(URI(base_url), URI::Generic)
        @identity = identity
      end

      sig { override.params(task_id: String, text: String, references: T::Array[String], due_at: Time, timezone: String, delivery_key: String).returns(Domains::FutureTasks::Dto::DeliveryReceipt) }
      def deliver(task_id:, text:, references:, due_at:, timezone:, delivery_key:)
        response = request(
          "POST", "/private/future-tasks/deliveries",
          { "task_id" => task_id, "text" => text, "references" => references, "due_at" => due_at.utc.iso8601, "timezone" => timezone, "delivery_key" => delivery_key }
        )
        receipt(response, delivery_key)
      end

      sig { override.params(delivery_key: String).returns(Domains::FutureTasks::Dto::BridgeResolution) }
      def reconcile(delivery_key:)
        response = request("GET", "/private/future-tasks/deliveries/#{URI.encode_uri_component(delivery_key)}", nil)
        return Domains::FutureTasks::Dto::BridgeResolution.new(terminal_failure: String(response.fetch("terminal_failure"))) if response.key?("terminal_failure")
        return Domains::FutureTasks::Dto::BridgeResolution.new unless response.key?("commander_item_id")

        Domains::FutureTasks::Dto::BridgeResolution.new(receipt: receipt(response, delivery_key))
      end

      sig { override.params(delivery_key: String, outcome: String).void }
      def record_outcome(delivery_key:, outcome:)
        request("POST", "/private/future-tasks/deliveries/#{URI.encode_uri_component(delivery_key)}/outcome", { "outcome" => outcome })
      end

      sig { params(method: String, path: String, body: T.nilable(T::Hash[String, T.untyped])).returns(T::Hash[String, T.untyped]) }
      private def request(method, path, body)
        target = @base_url + path
        request = Net::HTTP.const_get(method.capitalize).new(target, { "Authorization" => "Bearer #{@identity}", "Content-Type" => "application/json" })
        request.body = JSON.generate(body) if body
        response = Net::HTTP.start(target.host, target.port, use_ssl: target.scheme == "https", open_timeout: 2, read_timeout: 5) { |client| client.request(request) }
        raise "Commander bridge rejected delivery (HTTP #{response.code})" unless response.code.to_i.between?(200, 299)

        parsed = JSON.parse(response.body)
        raise "Commander bridge returned a non-object response" unless parsed.is_a?(Hash)

        parsed
      end

      sig { params(response: T::Hash[String, T.untyped], delivery_key: String).returns(Domains::FutureTasks::Dto::DeliveryReceipt) }
      private def receipt(response, delivery_key)
        returned_key = String(response.fetch("delivery_key"))
        raise "Commander bridge returned a mismatched delivery key" unless returned_key == delivery_key

        Domains::FutureTasks::Dto::DeliveryReceipt.new(delivery_key:, commander_item_id: String(response.fetch("commander_item_id")))
      end
    end
  end
end

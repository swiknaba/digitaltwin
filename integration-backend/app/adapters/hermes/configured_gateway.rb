# typed: strict
# frozen_string_literal: true

require "digest"
require "json"
require "net/http"
require "uri"

module Adapters
  module Hermes
    # The project-local Hermes adapter is the FutureTasks delivery boundary.
    # It owns the bearer credential and submits every delivery to the one
    # durable Commander session with an immutable delivery key.
    class ConfiguredGateway
      extend T::Sig

      include Adapters::OpenCode::Gateway

      sig { params(base_url: String).void }
      def initialize(base_url:)
        @base_url = T.let(URI(base_url), URI::Generic)
        unless @base_url.scheme == "http" && ["127.0.0.1", "localhost", "::1"].include?(@base_url.host)
          raise ArgumentError, "Hermes adapter URL must use HTTP loopback"
        end
      end

      sig { override.params(task_id: String, text: String, references: T::Array[String], due_at: Time, timezone: String, origin: String, attempt: Integer, delivery_key: String).returns(Domains::FutureTasks::Dto::DeliveryReceipt) }
      def deliver(task_id:, text:, references:, due_at:, timezone:, origin:, attempt:, delivery_key:)
        response = request("POST", "/deliveries", delivery_body(task_id: task_id, text: text, references: references, due_at: due_at, timezone: timezone, origin: origin, attempt: attempt, delivery_key: delivery_key))
        raise "Hermes adapter rejected future-task delivery (HTTP #{response.code})" unless response.code.to_i.between?(200, 299)

        receipt = Domains::FutureTasks::Dto::DeliveryReceipt.new(delivery_key: delivery_key, commander_item_id: commander_run_id(delivery_key))
        raise "Hermes adapter returned an unexpected delivery receipt" unless response.body.include?(receipt.commander_item_id)

        receipt
      end

      sig { override.params(delivery_key: String).returns(Domains::FutureTasks::Dto::BridgeResolution) }
      def reconcile(delivery_key:)
        response = request("GET", "/runs/#{commander_run_id(delivery_key)}", nil)
        return Domains::FutureTasks::Dto::BridgeResolution.new if response.code.to_i == 404

        raise "Hermes adapter rejected reconciliation (HTTP #{response.code})" unless response.code.to_i.between?(200, 299)

        Domains::FutureTasks::Dto::BridgeResolution.new(receipt: Domains::FutureTasks::Dto::DeliveryReceipt.new(delivery_key: delivery_key, commander_item_id: commander_run_id(delivery_key)))
      end

      sig { override.params(delivery_key: String, outcome: String).void }
      def record_outcome(delivery_key:, outcome:)
        response = request("POST", "/deliveries", { "delivery_key" => "outcome:#{delivery_key}:#{outcome}", "text" => "Future task #{delivery_key} was resolved as #{outcome}." })
        raise "Hermes adapter rejected future-task outcome (HTTP #{response.code})" unless response.code.to_i.between?(200, 299)
      end

      sig { params(task_id: String, text: String, references: T::Array[String], due_at: Time, timezone: String, origin: String, attempt: Integer, delivery_key: String).returns(T::Hash[String, T.any(String, Integer, T::Array[String])]) }
      private def delivery_body(task_id:, text:, references:, due_at:, timezone:, origin:, attempt:, delivery_key:)
        reference_text = references.empty? ? "none" : references.join(", ")
        { "delivery_key" => delivery_key, "text" => "Commander-directed scheduled check-in:\n#{text}\n\nTask: #{task_id}\nDue: #{due_at.utc.iso8601} (#{timezone})\nOrigin: #{origin}\nAttempt: #{attempt}\nReferences: #{reference_text}\nDelivery key: #{delivery_key}" }
      end

      sig { params(method: String, path: String, body: T.nilable(T::Hash[String, T.any(String, Integer, T::Array[String])])).returns(Net::HTTPResponse) }
      private def request(method, path, body)
        target = @base_url + path
        request = Net::HTTP.const_get(method.capitalize).new(target, { "Content-Type" => "application/json" })
        request.body = JSON.generate(body) if body
        Net::HTTP.start(target.host, target.port, use_ssl: false, open_timeout: 2, read_timeout: 5) { |client| client.request(request) }
      end

      sig { params(delivery_key: String).returns(String) }
      private def commander_run_id(delivery_key)
        "cmd_#{Digest::SHA256.hexdigest("delivery:#{delivery_key}")}"
      end
    end
  end
end

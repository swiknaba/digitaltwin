# typed: strict
# frozen_string_literal: true

module Adapters
  module OpenCode
    class UnavailableGateway
      extend T::Sig

      include Gateway

      sig { override.params(task_id: String, text: String, references: T::Array[String], due_at: Time, timezone: String, origin: String, attempt: Integer, delivery_key: String).returns(Domains::FutureTasks::Dto::DeliveryReceipt) }
      def deliver(task_id:, text:, references:, due_at:, timezone:, origin:, attempt:, delivery_key:)
        raise "OpenCode future-task delivery is not configured"
      end

      sig { override.params(delivery_key: String).returns(Domains::FutureTasks::Dto::BridgeResolution) }
      def reconcile(delivery_key:)
        raise "OpenCode future-task delivery is not configured"
      end

      sig { override.params(delivery_key: String, outcome: String).void }
      def record_outcome(delivery_key:, outcome:)
        raise "OpenCode future-task delivery is not configured"
      end
    end
  end
end

# typed: strict
# frozen_string_literal: true

module Adapters
  module CommanderBridge
    class UnavailableGateway
      extend T::Sig

      include Gateway

      sig { override.params(task_id: String, text: String, references: T::Array[String], due_at: Time, timezone: String, origin: String, attempt: Integer, delivery_key: String).returns(Domains::FutureTasks::Dto::DeliveryReceipt) }
      # rubocop:disable Lint/UnusedMethodArgument
      def deliver(task_id:, text:, references:, due_at:, timezone:, origin:, attempt:, delivery_key:)
        raise "Commander bridge delivery is not configured"
      end
      # rubocop:enable Lint/UnusedMethodArgument

      sig { override.params(delivery_key: String).returns(Domains::FutureTasks::Dto::BridgeResolution) }
      def reconcile(delivery_key:)
        raise "Commander bridge delivery is not configured for #{delivery_key[0, 0]}a delivery"
      end

      sig { override.params(delivery_key: String, outcome: String).void }
      def record_outcome(delivery_key:, outcome:)
        raise "Commander bridge delivery is not configured for #{delivery_key[0, 0]}a #{outcome[0, 0]}disposition"
      end
    end
  end
end

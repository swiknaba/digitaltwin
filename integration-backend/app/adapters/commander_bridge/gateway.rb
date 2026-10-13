# typed: strict
# frozen_string_literal: true

module Adapters
  module CommanderBridge
    # The bridge is the only future-task delivery boundary. Production wiring is
    # intentionally fail-closed until an operator-owned runtime is configured.
    module Gateway
      extend T::Sig
      extend T::Helpers

      interface!

      sig { abstract.params(task_id: String, text: String, references: T::Array[String], due_at: Time, timezone: String, delivery_key: String).returns(Domains::FutureTasks::Dto::DeliveryReceipt) }
      def deliver(task_id:, text:, references:, due_at:, timezone:, delivery_key:); end

      sig { abstract.params(delivery_key: String).returns(Domains::FutureTasks::Dto::BridgeResolution) }
      def reconcile(delivery_key:); end

      sig { abstract.params(delivery_key: String, outcome: String).void }
      def record_outcome(delivery_key:, outcome:); end
    end
  end
end

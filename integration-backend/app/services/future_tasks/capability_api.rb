# typed: strict
# frozen_string_literal: true

module Services
  module FutureTasks
    # Shared tool/API entry point. MCP and the global OpenCode tool provide only
    # task fields; verified capability context supplies every authority field.
    class CapabilityApi
      extend T::Sig

      sig { params(tasks: Domains::FutureTasks::Tasks, verifier: Adapters::FutureTasks::CapabilityVerifier, outcome_gateway: T.nilable(Adapters::CommanderBridge::Gateway)).void }
      def initialize(tasks:, verifier:, outcome_gateway: nil)
        @tasks = tasks
        @verifier = verifier
        @outcome_gateway = outcome_gateway
      end

      sig { params(token: String, idempotency_key: String, text: String, due_at: Time, timezone: String, local_time: String, references: T::Array[String]).returns(Domains::FutureTasks::Dto::TaskView) }
      def create(token:, idempotency_key:, text:, due_at:, timezone:, local_time:, references: [])
        capability = verify(token)
        @tasks.create(actor_id: capability.actor_id, origin: capability.conversation_id, idempotency_key:, text:, due_at:, timezone:, local_time:, references:)
      end

      sig { params(token: String, cursor: T.nilable(String), limit: Integer).returns(Domains::FutureTasks::Dto::TaskPage) }
      def list(token:, cursor: nil, limit: 50)
        capability = verify(token)
        @tasks.list(actor_id: capability.actor_id, cursor:, limit:)
      end

      sig { params(token: String, id: String).returns(T.nilable(Domains::FutureTasks::Dto::TaskView)) }
      def find(token:, id:)
        capability = verify(token)
        @tasks.find(actor_id: capability.actor_id, id:)
      end

      sig { params(token: String, id: String, expected_version: Integer, text: T.nilable(String), due_at: T.nilable(Time), timezone: T.nilable(String), local_time: T.nilable(String)).returns(Domains::FutureTasks::Dto::TaskView) }
      def update(token:, id:, expected_version:, text: nil, due_at: nil, timezone: nil, local_time: nil)
        capability = verify(token)
        @tasks.update(actor_id: capability.actor_id, id:, expected_version:, text:, due_at:, timezone:, local_time:)
      end

      sig { params(token: String, id: String, expected_version: Integer).returns(Domains::FutureTasks::Dto::TaskView) }
      def cancel(token:, id:, expected_version:)
        capability = verify(token)
        @tasks.cancel(actor_id: capability.actor_id, id:, expected_version:)
      end

      sig { params(token: String, id: String, expected_version: Integer, disposition_key: String, outcome: String, due_at: T.nilable(Time), timezone: T.nilable(String), local_time: T.nilable(String)).returns(Domains::FutureTasks::Dto::TaskView) }
      def record_disposition(token:, id:, expected_version:, disposition_key:, outcome:, due_at: nil, timezone: nil, local_time: nil)
        capability = verify(token)
        task = @tasks.record_disposition(actor_id: capability.actor_id, id:, expected_version:, disposition_key:, outcome:, due_at:, timezone:, local_time:)
        @outcome_gateway&.record_outcome(delivery_key: task.delivery_key, outcome: T.must(task.outcome))
        task
      end

      sig { params(token: String, id: String, expected_version: Integer, resolution_key: String, outcome: String, reason: T.nilable(String)).returns(Domains::FutureTasks::Dto::TaskView) }
      def resolve_uncertain(token:, id:, expected_version:, resolution_key:, outcome:, reason: nil)
        capability = verify(token)
        raise ArgumentError, "Owner capability is required" unless capability.owner

        @tasks.resolve_uncertain(actor_id: capability.actor_id, id:, expected_version:, resolution_key:, outcome:, reason:)
      end

      sig { params(token: String).returns(Adapters::FutureTasks::Capability) }
      private def verify(token) = @verifier.verify!(token:, audience: "future_tasks")
    end
  end
end

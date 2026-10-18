# typed: strict
# frozen_string_literal: true

module Adapters
  module FutureTasks
    # Thin global OpenCode-tool transport adapter. It shares the exact same API
    # service as MCP and cannot create local schedules in an unavailable Kirei.
    class OpencodeTool
      extend T::Sig

      sig { params(api: Services::FutureTasks::CapabilityApi).void }
      def initialize(api:)
        @api = api
      end

      sig { params(capability: String, idempotency_key: String, text: String, due_at: Time, timezone: String, local_time: String, references: T::Array[String]).returns(Domains::FutureTasks::Dto::TaskView) }
      def create(capability:, idempotency_key:, text:, due_at:, timezone:, local_time:, references: [])
        @api.create(token: capability, idempotency_key:, text:, due_at:, timezone:, local_time:, references:)
      end

      sig { params(capability: String, cursor: T.nilable(String), limit: Integer).returns(Domains::FutureTasks::Dto::TaskPage) }
      def list(capability:, cursor: nil, limit: 50) = @api.list(token: capability, cursor:, limit:)

      sig { params(capability: String, id: String).returns(T.nilable(Domains::FutureTasks::Dto::TaskView)) }
      def find(capability:, id:) = @api.find(token: capability, id:)

      sig { params(capability: String, id: String, expected_version: Integer, text: T.nilable(String), due_at: T.nilable(Time), timezone: T.nilable(String), local_time: T.nilable(String)).returns(Domains::FutureTasks::Dto::TaskView) }
      def update(capability:, id:, expected_version:, text: nil, due_at: nil, timezone: nil, local_time: nil) = @api.update(token: capability, id:, expected_version:, text:, due_at:, timezone:, local_time:)

      sig { params(capability: String, id: String, expected_version: Integer).returns(Domains::FutureTasks::Dto::TaskView) }
      def cancel(capability:, id:, expected_version:) = @api.cancel(token: capability, id:, expected_version:)

      sig { params(capability: String, id: String, expected_version: Integer, disposition_key: String, outcome: String, due_at: T.nilable(Time), timezone: T.nilable(String), local_time: T.nilable(String)).returns(Domains::FutureTasks::Dto::TaskView) }
      def record_disposition(capability:, id:, expected_version:, disposition_key:, outcome:, due_at: nil, timezone: nil, local_time: nil) = @api.record_disposition(token: capability, id:, expected_version:, disposition_key:, outcome:, due_at:, timezone:, local_time:)

      sig { params(capability: String, id: String, expected_version: Integer, resolution_key: String, outcome: String, reason: T.nilable(String)).returns(Domains::FutureTasks::Dto::TaskView) }
      def resolve_uncertain(capability:, id:, expected_version:, resolution_key:, outcome:, reason: nil) = @api.resolve_uncertain(token: capability, id:, expected_version:, resolution_key:, outcome:, reason:)
    end
  end
end

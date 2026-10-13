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

      sig { params(capability: String, idempotency_key: String, text: String, due_at: Time, timezone: String, local_time: String, references: T::Array[String], recurrence: T.nilable(String)).returns(Domains::FutureTasks::Dto::TaskView) }
      def create(capability:, idempotency_key:, text:, due_at:, timezone:, local_time:, references: [], recurrence: nil)
        @api.create(token: capability, idempotency_key:, text:, due_at:, timezone:, local_time:, references:, recurrence:)
      end
    end
  end
end

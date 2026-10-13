# typed: strict
# frozen_string_literal: true

module Adapters
  module FutureTasks
    # Thin MCP transport adapter. The MCP server supplies the bearer capability;
    # this adapter deliberately has no scheduler or actor parameters.
    class McpTool
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

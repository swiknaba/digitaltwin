# typed: strict
# frozen_string_literal: true

module Services
  module FutureTasks
    class DeliverDue
      extend T::Sig
      include Platform::Jobs::Handler

      sig { params(tasks: Domains::FutureTasks::Tasks, gateway: Adapters::CommanderBridge::Gateway).void }
      def initialize(tasks:, gateway:)
        @tasks = tasks
        @gateway = gateway
      end

      sig { override.params(job: Platform::Jobs::Dto::ClaimedJob).returns(Platform::Jobs::Dto::Decision) }
      def call(job:)
        execution_id = String(job.payload.fetch("execution_id"))
        @tasks.deliver(execution_id:, lease: job.lease, gateway: @gateway)
      end
    end
  end
end

# typed: strict
# frozen_string_literal: true

module Services
  module FutureTasks
    # At-least-once outbox publisher. The Node event key makes repeated delivery safe.
    class PublishOutcome
      extend T::Sig
      include Platform::Jobs::Handler

      sig { params(gateway: Adapters::CommanderBridge::Gateway).void }
      def initialize(gateway:)
        @gateway = gateway
      end

      sig { override.params(job: Platform::Jobs::Dto::ClaimedJob).returns(Platform::Jobs::Dto::Decision) }
      def call(job:)
        @gateway.record_outcome(delivery_key: String(job.payload.fetch("delivery_key")), outcome: String(job.payload.fetch("outcome")))
        Platform::Jobs::Dto::Decision.complete
      end
    end
  end
end

# typed: strict
# frozen_string_literal: true

module Domains
  module Workflows
    # Verified messages held while a workflow is paused or in review. Each
    # inbox record queues at most once (unique inbox_id).
    class QueuedMessages
      extend T::Sig

      sig { params(workflow_id: String, inbox_id: Integer, workflow_version: Integer).void }
      def enqueue(workflow_id:, inbox_id:, workflow_version:)
        Entities::QueuedMessage.query.insert(workflow_id: workflow_id, inbox_id: inbox_id, workflow_version: workflow_version)
      end

      # Oldest first.
      sig { params(workflow_id: String).returns(T::Array[Dto::QueuedMessageView]) }
      def pending(workflow_id:) = Records.queued_messages(Entities::QueuedMessage.query.where(workflow_id: workflow_id).order(:id))

      sig { params(id: Integer).void }
      def remove(id:)
        Entities::QueuedMessage.query.where(id: id).delete
      end
    end
  end
end

# typed: strict
# frozen_string_literal: true

module Domains
  module Workflows
    # Read access to workflows. "Active" means not archived; closed and
    # cancelled workflows stay active until their sessions stop.
    class Catalog
      extend T::Sig

      sig { params(id: String).returns(T.nilable(Dto::WorkflowView)) }
      def find(id:) = Records.workflows(Entities::Workflow.query.where(id: id)).first

      # Takes a row lock inside the caller's transaction.
      sig { params(id: String).returns(T.nilable(Dto::WorkflowView)) }
      def find_for_update(id:) = Records.workflows(Entities::Workflow.query.where(id: id).for_update).first

      sig { params(channel_id: String, thread_id: String).returns(T.nilable(Dto::WorkflowView)) }
      def active_in_thread(channel_id:, thread_id:)
        Records.workflows(active_query.where(channel_id: channel_id, thread_id: thread_id)).first
      end

      sig { returns(T::Array[Dto::WorkflowView]) }
      def active = Records.workflows(active_query.order(:created_at, :id))

      sig { params(inbox_id: Integer).returns(T::Array[String]) }
      def ids_for_source(inbox_id:) = Entities::Workflow.query.where(source_inbox_id: inbox_id).order(:id).select_map(:id)

      sig { returns(Sequel::Dataset) }
      private def active_query = Entities::Workflow.query.where(archived_at: nil)
    end
  end
end

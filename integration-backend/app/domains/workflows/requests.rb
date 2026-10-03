# typed: strict
# frozen_string_literal: true

module Domains
  module Workflows
    # Durable start requests. One verified inbox record starts at most one
    # request, and a replay must carry the same digest.
    class Requests
      extend T::Sig

      Outcome = T.type_alias { Kirei::Services::Result[Dto::RequestView] }

      sig { params(catalog: Catalog).void }
      def initialize(catalog: Catalog.new)
        @catalog = catalog
      end

      # Callers lock the inbox record first to serialize replays.
      sig do
        params(inbox_id: String, project_id: String, digest: String, parameters: Dto::RequestParameters, thread_id: T.nilable(String)).returns(Outcome)
      end
      def create(inbox_id:, project_id:, digest:, parameters:, thread_id:)
        existing = for_inbox(inbox_id: inbox_id)
        if existing
          return Kirei::Services::Result.new(result: existing) if existing.request_digest == digest

          return failure(Dto::ErrorCode::StartSourceBound, "Start source already bound")
        end

        id = SecureRandom.uuid
        values = { id: id, inbox_id: inbox_id, project_id: project_id, request_digest: digest, parameters: parameters.serialize, thread_id: thread_id }
        Entities::WorkflowRequest.wrap_jsonb_non_primivitives!(values)
        Entities::WorkflowRequest.query.insert(values)
        Kirei::Services::Result.new(result: T.must(find(id: id)))
      end

      sig { params(id: String).returns(T.nilable(Dto::RequestView)) }
      def find(id:) = Records.requests(Entities::WorkflowRequest.query.where(id: id)).first

      sig { params(inbox_id: String).returns(T.nilable(Dto::RequestView)) }
      def for_inbox(inbox_id:) = Records.requests(Entities::WorkflowRequest.query.where(inbox_id: inbox_id)).first

      sig { params(id: String, state: Dto::RequestState, reason: T.nilable(String)).void }
      def mark(id:, state:, reason:)
        Entities::WorkflowRequest.query.where(id: id).update(state: state.serialize, reason: reason)
      end

      # Records the verified start thread and requeues the request.
      sig { params(id: String, thread_id: String).void }
      def record_thread(id:, thread_id:)
        Entities::WorkflowRequest.query.where(id: id).update(thread_id: thread_id, state: Dto::RequestState::Queued.serialize, reason: nil)
      end

      # Creates the request's workflow once. A request that is already bound
      # returns its workflow; an active workflow in the same thread blocks it.
      sig { params(id: String, workflow: Dto::WorkflowDraft).returns(Kirei::Services::Result[Dto::WorkflowView]) }
      def bind(id:, workflow:)
        Entities::WorkflowRequest.db.transaction do
          request = Records.requests(Entities::WorkflowRequest.query.where(id: id).for_update).first
          next workflow_failure(Dto::ErrorCode::MissingRequest, "Missing workflow request") unless request

          bound_id = request.workflow_id
          next Kirei::Services::Result.new(result: T.must(@catalog.find(id: bound_id))) if bound_id
          if @catalog.active_in_thread(channel_id: workflow.channel_id, thread_id: workflow.thread_id)
            next workflow_failure(Dto::ErrorCode::ThreadOwned, "Active thread already owns a workflow")
          end

          # Kirei's human id generator; the branch and worktree path embed the id,
          # so it is generated before `create` instead of inside it.
          workflow_id = Entities::Workflow.generate_human_id
          Entities::Workflow.create(id: workflow_id, project_id: workflow.project_id, channel_id: workflow.channel_id, thread_id: workflow.thread_id,
                                    branch: "digitaltwin/#{workflow_id}", worktree_path: File.join(workflow.worktree_root, workflow_id),
                                    source_inbox_id: workflow.source_inbox_id, role_configurations: workflow.role_configurations.serialize)
          Entities::WorkflowRequest.query.where(id: id).update(workflow_id: workflow_id)
          Kirei::Services::Result.new(result: T.must(@catalog.find(id: workflow_id)))
        end
      end

      sig { params(code: Dto::ErrorCode, detail: String).returns(Outcome) }
      private def failure(code, detail)
        Kirei::Services::Result.new(errors: Platform::Failure.call(code: code, detail: detail))
      end

      sig { params(code: Dto::ErrorCode, detail: String).returns(Kirei::Services::Result[Dto::WorkflowView]) }
      private def workflow_failure(code, detail)
        Kirei::Services::Result.new(errors: Platform::Failure.call(code: code, detail: detail))
      end
    end
  end
end

# typed: strict
# frozen_string_literal: true

module Domains
  module Workflows
    # Human approvals of exact artifact commits. One chat post approves at most
    # one (workflow, gate, commit); a second post for the same commit keeps the
    # first approval.
    class Approvals
      extend T::Sig

      Outcome = T.type_alias { Kirei::Services::Result[Dto::ApprovalView] }

      sig do
        params(workflow_id: String, gate: Dto::Gate, target_commit: String, user_id: String, channel_id: String, post_id: String).returns(Outcome)
      end
      def record(workflow_id:, gate:, target_commit:, user_id:, channel_id:, post_id:)
        Entities::Approval.db.transaction do
          old = Records.approvals(Entities::Approval.query.where(post_id: post_id)).first
          if old
            next Kirei::Services::Result.new(result: old) if old.workflow_id == workflow_id && old.gate == gate && old.target_commit == target_commit

            next failure(Dto::ErrorCode::ApprovalSourceBound, "Source approval already bound")
          end

          Entities::Approval.query.insert_conflict(target: %i[workflow_id kind target_commit]).insert(
            workflow_id: workflow_id, kind: gate.serialize, target_commit: target_commit, user_id: user_id, channel_id: channel_id, post_id: post_id
          )
          Kirei::Services::Result.new(result: T.must(find(workflow_id: workflow_id, gate: gate, commit: target_commit)))
        end
      end

      sig { params(workflow_id: String, gate: Dto::Gate, commit: String).returns(T.nilable(Dto::ApprovalView)) }
      def find(workflow_id:, gate:, commit:)
        Records.approvals(Entities::Approval.query.where(workflow_id: workflow_id, kind: gate.serialize, target_commit: commit)).first
      end

      sig { params(code: Dto::ErrorCode, detail: String).returns(Outcome) }
      private def failure(code, detail)
        Kirei::Services::Result.new(errors: Platform::Failure.call(code: code, detail: detail))
      end
    end
  end
end

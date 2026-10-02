# typed: strict
# frozen_string_literal: true

module Services
  module Master
    module Dto
      # Expected failure codes of Master use cases.
      class ErrorCode < T::Enum
        enums do
          UnexpectedFields = new("unexpected_fields")
          InvalidArguments = new("invalid_arguments")
          UnsupportedControl = new("unsupported_control")
          MissingWorkflow = new("missing_workflow")
          VersionChanged = new("version_changed")
          InvalidReply = new("invalid_reply")
          ReplyChanged = new("reply_changed")
          AlreadyCompleted = new("already_completed")
          Busy = new("busy")
          UnknownRequest = new("unknown_request")
          RecoveryRejected = new("recovery_rejected")
          EffectUncertain = new("effect_uncertain")
          SessionUnsettled = new("session_unsettled")
          MissingSource = new("missing_source")
          SourceChanged = new("source_changed")
          InterpretationRejected = new("interpretation_rejected")
          SelectionRejected = new("selection_rejected")
          InactiveWorkflow = new("inactive_workflow")
          MembershipRequired = new("membership_required")
          MissingFollowup = new("missing_followup")
          OutcomeBound = new("outcome_bound")
          LeaseLive = new("lease_live")
          ApprovalRejected = new("approval_rejected")
          ApprovalStale = new("approval_stale")
        end
      end
    end
  end
end

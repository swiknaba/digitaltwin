# typed: strict
# frozen_string_literal: true

module Domains
  module Workflows
    module Dto
      # Expected failure codes of the workflows context.
      class ErrorCode < T::Enum
        enums do
          MissingWorkflow = new("missing_workflow")
          VersionChanged = new("version_changed")
          Inactive = new("inactive")
          CannotPause = new("cannot_pause")
          NotPaused = new("not_paused")
          NotDelivered = new("not_delivered")
          AlreadyClosed = new("already_closed")
          PhaseMismatch = new("phase_mismatch")
          MissingRequest = new("missing_request")
          StartSourceBound = new("start_source_bound")
          ThreadOwned = new("thread_owned")
          ApprovalSourceBound = new("approval_source_bound")
        end
      end
    end
  end
end

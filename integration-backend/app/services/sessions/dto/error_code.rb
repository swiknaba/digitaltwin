# typed: strict
# frozen_string_literal: true

module Services
  module Sessions
    module Dto
      # Expected failure codes of session use cases.
      class ErrorCode < T::Enum
        enums do
          InvalidCallback = new("invalid_callback")
          InvalidSession = new("invalid_session")
          InactiveWorkflow = new("inactive_workflow")
          InactiveRole = new("inactive_role")
          StaleGeneration = new("stale_generation")
          CallbackKeyReused = new("callback_key_reused")
          MalformedRecord = new("malformed_record")
          WorkflowRoleRequired = new("workflow_role_required")
          MissingWorkflow = new("missing_workflow")
          MissingSource = new("missing_source")
          IncompleteConfiguration = new("incomplete_configuration")
          InactiveRenewal = new("inactive_renewal")
          SessionReplaced = new("session_replaced")
          IdentityUnproven = new("identity_unproven")
          CredentialChanged = new("credential_changed")
          UnknownOperation = new("unknown_operation")
          RecoveryRejected = new("recovery_rejected")
          OperationLeaseLive = new("operation_lease_live")
          EvidenceRejected = new("evidence_rejected")
        end
      end
    end
  end
end

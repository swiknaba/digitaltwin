# typed: strict
# frozen_string_literal: true

module Services
  # Maps each worker job kind to its use case. commander.dispatch exists only
  # when a commander role is configured. mattermost.post is not mapped here;
  # bin/worker adds Composition#deliver_outbox for it.
  class JobHandlers
    extend T::Sig

    Kind = Platform::Jobs::Dto::JobKind
    HandlerMap = T.type_alias { T::Hash[Platform::Jobs::Dto::JobKind, Platform::Jobs::Handler] }

    sig { params(composition: Composition).void }
    def initialize(composition:)
      @composition = composition
    end

    sig { returns(HandlerMap) }
    def call
      handlers = T.let({
                         Kind::CommanderPrompt => @composition.handle_commander_prompt,
                         Kind::WorkflowPrompt => @composition.handle_workflow_prompt,
                         Kind::SessionFollowup => @composition.deliver_followup,
                         Kind::WorkflowProvision => @composition.provision,
                         Kind::SessionStart => @composition.execute_operation,
                         Kind::SessionStop => @composition.execute_operation,
                         Kind::ReviewPrompt => @composition.dispatch_review,
                         Kind::ReviewRelease => @composition.release_queued,
                         Kind::ReviewCallback => @composition.apply_callback,
                         Kind::CommanderControl => @composition.control,
                         Kind::SessionRenew => @composition.renew,
                         Kind::WorkflowPhasePrompt => @composition.dispatch_phase_prompt,
                         Kind::WorkflowStart => @composition.start_existing,
                         Kind::WorkflowPause => @composition.control,
                         Kind::WorkflowResume => @composition.control,
                         Kind::WorkflowFinish => @composition.control,
                         Kind::WorkflowCancel => @composition.control,
                         Kind::WorkflowApprove => @composition.approve_current
                       }, HandlerMap)
      dispatch = @composition.dispatch
      handlers[Kind::CommanderDispatch] = dispatch if dispatch
      handlers
    end
  end
end

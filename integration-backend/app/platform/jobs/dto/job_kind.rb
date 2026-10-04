# typed: strict
# frozen_string_literal: true

module Platform
  module Jobs
    module Dto
      # Persisted job kind strings; values are part of the durable queue contract.
      class JobKind < T::Enum
        enums do
          CommanderPrompt = new("commander.prompt")
          CommanderDispatch = new("commander.dispatch")
          CommanderControl = new("commander.control")
          WorkflowPrompt = new("workflow.prompt")
          WorkflowStart = new("workflow.start")
          WorkflowApprove = new("workflow.approve")
          WorkflowPause = new("workflow.pause")
          WorkflowResume = new("workflow.resume")
          WorkflowFinish = new("workflow.finish")
          WorkflowCancel = new("workflow.cancel")
          WorkflowProvision = new("workflow.provision")
          WorkflowPhasePrompt = new("workflow.phase_prompt")
          SessionStart = new("session.start")
          SessionStop = new("session.stop")
          SessionRenew = new("session.renew")
          SessionFollowup = new("session.followup")
          ReviewPrompt = new("review.prompt")
          ReviewRelease = new("review.release")
          ReviewCallback = new("review.callback")
          MattermostPost = new("mattermost.post")
        end
      end
    end
  end
end

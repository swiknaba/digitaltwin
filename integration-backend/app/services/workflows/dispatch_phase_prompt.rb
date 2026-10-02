# typed: strict
# frozen_string_literal: true

module Services
  module Workflows
    # Handles workflow.phase_prompt: prompts the workflow's existing Writer
    # once per version, after the gate approvals and the source still hold.
    # A busy Writer or a paused workflow defers the job.
    class DispatchPhasePrompt
      extend T::Sig
      include Platform::Jobs::Handler

      Code = Dto::ErrorCode
      Decision = Platform::Jobs::Dto::Decision
      Gate = Domains::Workflows::Dto::Gate
      Phase = Domains::Workflows::Dto::Phase
      Writer = Domains::Sessions::Dto::SessionRole::Writer
      Outcome = T.type_alias { Kirei::Services::Result[Decision] }
      APPROVED_BEFORE = T.let({ Phase::PlanWriting => Gate::Spec, Phase::Implementation => Gate::Plan }.freeze, T::Hash[Phase, Gate])

      sig do
        params(source: Domains::Messaging::VerifyHumanSource, herdr: Adapters::Herdr::Client, evidence: Adapters::Git::Evidence,
               policy: Domains::Workflows::Policy, catalog: Domains::Workflows::Catalog, approvals: Domains::Workflows::Approvals,
               registry: Domains::Sessions::Registry, rounds: Domains::Reviews::Rounds).void
      end
      def initialize(source:, herdr:, evidence:, policy: Domains::Workflows::Policy.new, catalog: Domains::Workflows::Catalog.new,
                     approvals: Domains::Workflows::Approvals.new, registry: Domains::Sessions::Registry.new, rounds: Domains::Reviews::Rounds.new)
        @source = source
        @herdr = herdr
        @verify_sessions = T.let(VerifySessions.new(herdr: herdr), VerifySessions)
        @prior_approvals = T.let(VerifyPriorApprovals.new(evidence: evidence, approvals: approvals), VerifyPriorApprovals)
        @rounds = rounds
        @policy = policy
        @catalog = catalog
        @approvals = approvals
        @registry = registry
      end

      sig { override.params(job: Platform::Jobs::Dto::ClaimedJob).returns(Decision) }
      def call(job:)
        Kirei::Services::Runner.call(self.class.name.to_s) do
          payload = Domains::Workflows::Dto::PhasePromptJob.from_hash(job.payload, true)
          Platform::Unwrap.call(Platform::Lock.new.call(key: payload.workflow_id) { dispatch(payload, job.lease) })
        end
      end

      sig { params(payload: Domains::Workflows::Dto::PhasePromptJob, lease: Platform::Jobs::Lease).returns(Outcome) }
      private def dispatch(payload, lease)
        workflow = @catalog.find(id: payload.workflow_id)
        return failure(Code::MissingWorkflow, "Missing workflow") unless workflow
        return decided(Decision.block("Live Writer dispatch evidence required")) unless @policy.dispatch_allowed?
        return decided(Decision.defer("Paused")) if workflow.phase == Phase::Paused
        return decided(Decision.complete) unless payload.version == workflow.version
        return failure(Code::PhaseChanged, "Phase changed") unless workflow.phase.writing?
        return decided(Decision.defer("Writer busy")) if writer_busy?(workflow)

        sessions = @verify_sessions.call(workflow_id: workflow.id, role: Writer)
        return Kirei::Services::Result.new(errors: sessions.errors) if sessions.failed?

        writer = sessions.result.first
        return failure(Code::SessionMissing, "Writer session missing") unless writer

        inbox_id = workflow.source_inbox_id
        return failure(Code::MissingSource, "Missing verified source") unless inbox_id

        verified = @source.call(inbox_id: inbox_id, destination: workflow.channel_id)
        return Kirei::Services::Result.new(errors: verified.errors) if verified.failed?

        approved = approved_gate(workflow)
        return approved if approved.failed?
        raise IOError, "Dispatch lease lost" unless lease.begin_effect

        @herdr.prompt(pane_id: writer.pane_id, text: prompt(workflow, verified.result.body))
        decided(Decision.complete)
      end

      sig { params(workflow: Domains::Workflows::Dto::WorkflowView).returns(T::Boolean) }
      private def writer_busy?(workflow)
        writer = @registry.active(workflow_id: workflow.id, role: Writer).first
        return false unless writer

        live = @herdr.pane(writer.pane_id)
        live.agent_status == Adapters::Herdr::Dto::AgentStatus::Working && live.agent_session&.serialize == writer.runtime_identity&.serialize
      end

      # Plan writing needs the approved spec; implementation needs the approved plan.
      sig { params(workflow: Domains::Workflows::Dto::WorkflowView).returns(Outcome) }
      private def approved_gate(workflow)
        gate = APPROVED_BEFORE[workflow.phase]
        return decided(Decision.complete) unless gate

        review = @rounds.latest(workflow_id: workflow.id, gate: gate)
        unless review && @approvals.find(workflow_id: workflow.id, gate: gate, commit: review.target_commit)
          return failure(Code::ApprovalMissing, "Required artifact approval missing")
        end

        prior = @prior_approvals.call(workflow: workflow, gates: gate.approved_gates)
        return Kirei::Services::Result.new(errors: prior.errors) if prior.failed?

        decided(Decision.complete)
      end

      sig { params(workflow: Domains::Workflows::Dto::WorkflowView, request: String).returns(String) }
      private def prompt(workflow, request)
        feedback = @rounds.latest_changes_requested(workflow_id: workflow.id)
        corrective = feedback ? "Read corrective feedback in #{feedback.review_path} at #{feedback.review_commit} for target #{feedback.target_commit}. " : ""
        corrective + "Work only in #{workflow.worktree_path} on #{workflow.branch}. " \
                     "Current phase: #{workflow.phase.serialize}. " \
                     "Human request: #{request}\nWrite docs/spec.md then docs/plan.md in their respective phases; implementation requires approved spec and plan. " \
                     "Report exact clean commits via artifact-ready. " \
                     "Stop changes during review. " \
                     "Do not create independent sessions."
      end

      sig { params(decision: Decision).returns(Outcome) }
      private def decided(decision) = Kirei::Services::Result.new(result: decision)

      sig { params(code: Code, detail: String).returns(Outcome) }
      private def failure(code, detail)
        Kirei::Services::Result.new(errors: Platform::Failure.call(code: code, detail: detail))
      end
    end
  end
end

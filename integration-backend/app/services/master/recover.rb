# typed: strict
# frozen_string_literal: true

module Services
  module Master
    # Completes an uncertain Master request on the exact recover-master command
    # of its original human, once every workflow and session effect of that
    # source is settled and the Controller conversation is positively settled.
    # Queued requests of the session are released for dispatch.
    class Recover
      extend T::Sig

      Code = Dto::ErrorCode
      State = Domains::Commander::Dto::MasterRequestState
      Identity = Adapters::Herdr::ConversationIdentity
      Outcome = T.type_alias { Kirei::Services::Result[String] }

      sig do
        params(source: Domains::Messaging::VerifyHumanSource, herdr: Adapters::Herdr::Client, requests: Domains::Commander::MasterRequests,
               registry: Domains::Sessions::Registry, operations: Domains::Sessions::Operations, inbox: Domains::Messaging::Inbox,
               catalog: Domains::Workflows::Catalog, workflow_requests: Domains::Workflows::Requests, rounds: Domains::Reviews::Rounds,
               jobs: Platform::Jobs::Store, lock: Platform::Lock, transaction: Platform::Transaction, handle: String).void
      end
      def initialize(source:, herdr:, requests: Domains::Commander::MasterRequests.new, registry: Domains::Sessions::Registry.new,
                     operations: Domains::Sessions::Operations.new, inbox: Domains::Messaging::Inbox.new, catalog: Domains::Workflows::Catalog.new,
                     workflow_requests: Domains::Workflows::Requests.new, rounds: Domains::Reviews::Rounds.new, jobs: Platform::Jobs::Store.new,
                     lock: Platform::Lock.new, transaction: Platform::Transaction.new, handle: ENV.fetch("AGENT_HANDLE", "agent"))
        @source = source
        @herdr = herdr
        @requests = requests
        @registry = registry
        @operations = operations
        @inbox = inbox
        @catalog = catalog
        @workflow_requests = workflow_requests
        @rounds = rounds
        @jobs = jobs
        @lock = lock
        @transaction = transaction
        @handle = handle
      end

      sig { params(request_id: String, inbox_id: String).returns(Outcome) }
      def call(request_id:, inbox_id:)
        Kirei::Services::Runner.call(self.class.name.to_s) do
          r = @requests.find(id: request_id)
          next failure(Code::UnknownRequest, "Unknown Master request") unless r

          original = T.must(@inbox.find(id: r.inbox_id))
          verified = @source.call(inbox_id: inbox_id, destination: original.channel_id)
          next Kirei::Services::Result.new(errors: verified.errors) if verified.failed?

          d = verified.result
          unless d.actor.user_id == original.user_id && d.body == "@#{@handle} recover-master #{request_id}"
            next failure(Code::RecoveryRejected, "Recovery requires the original human's exact request binding")
          end

          @lock.call(key: "controller") { recover(r, original, inbox_id) }
        rescue Platform::Lock::Busy => error
          failure(Code::Busy, error.message)
        end
      end

      sig { params(r: Domains::Commander::Dto::MasterRequestView, original: Domains::Messaging::Dto::InboxRecord, inbox_id: String).returns(Outcome) }
      private def recover(r, original, inbox_id)
        return failure(Code::RecoveryRejected, "Request does not require recovery") unless @requests.find(id: r.id)&.state == State::Uncertain

        workflow_ids = @catalog.ids_for_source(inbox_id: original.id)
        start = @workflow_requests.for_inbox(inbox_id: original.id)
        start_uncertain = start && [Domains::Workflows::Dto::RequestState::Sending, Domains::Workflows::Dto::RequestState::Uncertain].include?(start.state)
        if start_uncertain || @rounds.unsettled_dispatch?(workflow_ids: workflow_ids)
          return failure(Code::EffectUncertain, "Workflow effect still uncertain")
        end
        return failure(Code::EffectUncertain, "Session effect still uncertain") if @operations.unsettled_in_workflows?(workflow_ids: workflow_ids)

        s = @registry.find(id: r.session_id)
        s = nil unless s&.active
        live = s && @herdr.pane(s.pane_id)
        unless s && live && Identity.same?(s.runtime_identity, live.agent_session) && live.agent_status.settled?
          return failure(Code::SessionUnsettled, "Master session not positively settled")
        end

        @transaction.call do
          @requests.mark(id: r.id, state: State::Complete, reason: "Recovered by verified human source #{inbox_id}")
          @requests.in_state(session_id: r.session_id, state: State::Queued).each do |queued|
            job = @jobs.find_by_key(dispatch_key: "master:dispatch:#{queued.id}")
            @jobs.requeue_blocked(id: job.id) if job
          end
        end
        Kirei::Services::Result.new(result: State::Complete.serialize)
      end

      sig { params(code: Code, detail: String).returns(Outcome) }
      private def failure(code, detail)
        Kirei::Services::Result.new(errors: Platform::Failure.call(code: code, detail: detail))
      end
    end
  end
end

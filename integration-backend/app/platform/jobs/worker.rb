# typed: strict
# frozen_string_literal: true

module Platform
  module Jobs
    class Worker
      extend T::Sig

      UNCONFIGURED = "Task 1 live dispatch/delivery evidence pending or handler unconfigured"

      sig { params(handlers: T::Hash[Dto::JobKind, Handler], store: Store).void }
      def initialize(handlers: {}, store: Store.new)
        @store = store
        @handlers = handlers
        @worker_id = T.let("#{Process.pid}:#{SecureRandom.uuid}", String)
      end

      sig { void }
      def run
        loop do
          tick
          Health.touch("worker")
          Async::Task.current.sleep(0.25)
        end
      end

      sig { returns(T::Boolean) }
      def tick
        job = T.let(nil, T.nilable(Dto::ClaimedJob))
        heartbeat = T.let(nil, T.nilable(Async::Task))
        job = @store.claim(worker_id: @worker_id)
        return false unless job

        lease = job.lease
        handler = @handlers[job.kind]
        unless handler
          @store.block(id: job.id, lease_token: lease.token, reason: UNCONFIGURED)
          return true
        end
        heartbeat = Async::Task.current.async do |task|
          loop do
            task.sleep(10)
            break unless lease.heartbeat
          end
        end
        apply(job, handler.call(job: job))
        true
      rescue StandardError => error
        @store.retry(id: job.id, lease_token: job.lease.token, error: error.class.to_s) if job
        false
      ensure
        heartbeat&.stop
      end

      private

      # A defer or block that cannot apply (effect already began, or lease lost)
      # falls through to completion, matching the pre-Decision handler contract.
      sig { params(job: Dto::ClaimedJob, decision: Dto::Decision).void }
      def apply(job, decision)
        token = job.lease.token
        reason = decision.reason.to_s
        action = decision.action
        settled = case action
                  when Dto::DecisionAction::Complete then false
                  when Dto::DecisionAction::Defer then @store.defer(id: job.id, lease_token: token, reason: reason)
                  when Dto::DecisionAction::Block then @store.block(id: job.id, lease_token: token, reason: reason)
                  else T.absurd(action)
                  end
        @store.complete(id: job.id, lease_token: token) unless settled
      end
    end
  end
end

# typed: strict
# frozen_string_literal: true

module Domains
  module Jobs
    class Worker
      extend T::Sig

      module Handler
        extend T::Helpers
        extend T::Sig

        interface!

        sig { abstract.params(job: Job, store: Store).returns(Object) }
        def call(job, store); end
      end

      sig { params(handlers: T::Hash[String, Handler]).void }
      def initialize(handlers: {})
        @store = T.let(Store.new, Store)
        @handlers = T.let(handlers, T::Hash[String, Handler])
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
        job = T.let(nil, T.nilable(Job))
        heartbeat = T.let(nil, T.nilable(Async::Task))
        job = @store.claim(worker_id: @worker_id)
        return false unless job

        handler = @handlers[job.kind]
        lease_token = job.lease_token
        raise IOError, "Claimed job lacks a lease token" unless lease_token

        unless handler
          @store.block(id: job.id, lease_token: lease_token,
                       reason: "Task 1 live dispatch/delivery evidence pending or handler unconfigured")
          return true
        end
        heartbeat = Async::Task.current.async do |task|
          loop do
            task.sleep(10)
            break unless @store.heartbeat(id: job.id, lease_token: lease_token)
          end
        end
        # Handlers explicitly mark external effects before the network call.
        handler.call(job, @store)
        @store.complete(id: job.id, lease_token: lease_token)
        true
      rescue StandardError => error
        if job
          lease_token = job.lease_token
          @store.retry(id: job.id, lease_token: lease_token, error: error.class.to_s) if lease_token
        end
        false
      ensure
        heartbeat&.stop
      end
    end
  end
end

# frozen_string_literal: true

module Domains
  module Jobs
    class Worker
      def initialize(db, handlers: {})
        @db, @store, @handlers = db, Store.new(db), handlers
        @worker_id = "#{Process.pid}:#{SecureRandom.uuid}"
      end

      def run
        loop do
          tick
          Health.touch("worker")
          Async::Task.current.sleep(0.25)
        end
      end

      def tick
        job = @store.claim(worker_id: @worker_id)
        return false unless job

        handler = @handlers[job[:kind]]
        unless handler
          @store.block(id: job[:id], lease_token: job[:lease_token],
                       reason: "Task 1 live dispatch/delivery evidence pending or handler unconfigured")
          return true
        end
        heartbeat = Async::Task.current.async do |task|
          loop do
            task.sleep(10)
            break unless @store.heartbeat(id: job[:id], lease_token: job[:lease_token])
          end
        end
        # Handlers explicitly mark external effects before the network call.
        handler.call(job, @store)
        @store.complete(id: job[:id], lease_token: job[:lease_token])
        true
      rescue StandardError => e
        @store.retry(id: job[:id], lease_token: job[:lease_token], error: e.class.name) if job
        false
      ensure
        heartbeat&.stop
      end
    end
  end
end

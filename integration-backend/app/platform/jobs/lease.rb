# typed: strict
# frozen_string_literal: true

module Platform
  module Jobs
    # The claimed job's lease. Handlers call `begin_effect` immediately before
    # an external effect; a false result means the lease was lost.
    class Lease
      extend T::Sig

      sig { returns(String) }
      attr_reader :job_id

      sig { returns(String) }
      attr_reader :token

      sig { params(store: Store, job_id: String, token: String).void }
      def initialize(store:, job_id:, token:)
        @store = store
        @job_id = job_id
        @token = token
      end

      sig { params(now: Time).returns(T::Boolean) }
      def begin_effect(now: Time.now) = @store.begin_effect(id: @job_id, lease_token: @token, now: now)

      sig { params(now: Time).returns(T::Boolean) }
      def heartbeat(now: Time.now) = @store.heartbeat(id: @job_id, lease_token: @token, now: now)
    end
  end
end

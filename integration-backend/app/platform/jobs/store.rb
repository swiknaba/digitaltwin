# typed: strict
# frozen_string_literal: true

module Platform
  module Jobs
    # Durable, idempotent job queue with leases. A job whose external effect
    # began is never retried automatically; it becomes `uncertain`.
    class Store
      extend T::Sig

      BACKOFF = T.let([1, 5, 15, 60].freeze, T::Array[Integer])
      ATTEMPT_BUDGET = 5
      LEASE_SECONDS = 30

      sig { params(kind: Dto::JobKind, payload: T::Struct, dispatch_key: String, available_at: Time).returns(String) }
      def enqueue(kind:, payload:, dispatch_key:, available_at: Time.now)
        data = T.let(payload.serialize, Platform::Json::Scalars)
        job = begin
          Entities::Job.db.transaction(savepoint: true) do
            Entities::Job.create(id: SecureRandom.uuid, kind: kind.serialize, payload: data, dispatch_key: dispatch_key, available_at: available_at)
          end
        rescue Sequel::UniqueConstraintViolation
          T.must(Entities::Job.find_by(dispatch_key: dispatch_key))
        end
        raise Errors::DispatchKeyReused, "Dispatch key reused with changed content" unless job.kind == kind && job.payload == data

        job.id
      end

      sig { params(worker_id: String, now: Time).returns(T.nilable(Dto::ClaimedJob)) }
      def claim(worker_id:, now: Time.now)
        Entities::Job.db.transaction do
          expired = with_status(Dto::JobStatus::Running).where(Sequel[:jobs][:lease_expires_at] <= now)
          expired.exclude(effect_started_at: nil).update(status: Dto::JobStatus::Uncertain.serialize, last_error: "Expired after external effect began")
          expired.where(effect_started_at: nil, attempts: ATTEMPT_BUDGET).update(status: Dto::JobStatus::Blocked.serialize, last_error: "Attempt budget exhausted")
          expired.where(effect_started_at: nil).exclude(attempts: ATTEMPT_BUDGET).update(status: Dto::JobStatus::Pending.serialize, lease_token: nil)
          row = with_status(Dto::JobStatus::Pending).where(Sequel[:jobs][:available_at] <= now).order(:available_at, :id).for_update.skip_locked.first
          return nil unless row

          job = T.must(Entities::Job.resolve([row]).first)
          token = SecureRandom.uuid
          Entities::Job.query.where(id: job.id).update(
            status: Dto::JobStatus::Running.serialize,
            worker_id: worker_id,
            lease_token: token,
            lease_expires_at: now + LEASE_SECONDS,
            attempts: job.attempts + 1
          )
          Dto::ClaimedJob.new(id: job.id, kind: job.kind, payload: job.payload, attempts: job.attempts + 1,
                              lease: Lease.new(store: self, job_id: job.id, token: token))
        end
      end

      sig { params(id: String, lease_token: String, now: Time).returns(T::Boolean) }
      def complete(id:, lease_token:, now: Time.now)
        live(id, lease_token, now).update(status: Dto::JobStatus::Complete.serialize, lease_token: nil, lease_expires_at: nil) == 1
      end

      sig { params(id: String, lease_token: String, now: Time).returns(T::Boolean) }
      def heartbeat(id:, lease_token:, now: Time.now) = live(id, lease_token, now).update(lease_expires_at: now + LEASE_SECONDS) == 1

      sig { params(id: String, lease_token: String, now: Time).returns(T::Boolean) }
      def begin_effect(id:, lease_token:, now: Time.now) = live(id, lease_token, now).where(effect_started_at: nil).update(effect_started_at: now) == 1

      sig { params(id: String, lease_token: String, error: String, now: Time).returns(T::Boolean) }
      def retry(id:, lease_token:, error:, now: Time.now)
        Entities::Job.db.transaction do
          row = live(id, lease_token, now).for_update.first
          return false unless row

          job = T.must(Entities::Job.resolve([row]).first)
          status = if job.effect_started_at
                     Dto::JobStatus::Uncertain
                   elsif job.attempts >= ATTEMPT_BUDGET
                     Dto::JobStatus::Blocked
                   else
                     Dto::JobStatus::Pending
                   end
          Entities::Job.query.where(id: id).update(
            status: status.serialize,
            lease_token: nil,
            lease_expires_at: nil,
            available_at: now + BACKOFF.fetch([job.attempts - 1, BACKOFF.length - 1].min),
            last_error: error[0, 512]
          )
          true
        end
      end

      sig { params(id: String, lease_token: String, reason: String, now: Time).returns(T::Boolean) }
      def defer(id:, lease_token:, reason:, now: Time.now)
        Entities::Job.db.transaction do
          row = live(id, lease_token, now).where(effect_started_at: nil).for_update.first
          return false unless row

          job = T.must(Entities::Job.resolve([row]).first)
          Entities::Job.query.where(id: job.id).update(status: Dto::JobStatus::Pending.serialize, lease_token: nil, lease_expires_at: nil,
                                                       available_at: now + 2, attempts: [job.attempts - 1, 0].max, last_error: reason) == 1
        end
      end

      sig { params(id: String, lease_token: String, reason: String, now: Time).returns(T::Boolean) }
      def block(id:, lease_token:, reason:, now: Time.now)
        live(id, lease_token, now).update(status: Dto::JobStatus::Blocked.serialize, last_error: reason, lease_token: nil, lease_expires_at: nil) == 1
      end

      sig { params(id: String).returns(T.nilable(Dto::JobSnapshot)) }
      def find(id:) = snapshot(Entities::Job.find_by(id: id))

      sig { params(dispatch_key: String).returns(T.nilable(Dto::JobSnapshot)) }
      def find_by_key(dispatch_key:) = snapshot(Entities::Job.find_by(dispatch_key: dispatch_key))

      # Releases a blocked job whose effect never began, with a fresh attempt budget.
      sig { params(id: String).returns(T::Boolean) }
      def requeue_blocked(id:)
        with_status(Dto::JobStatus::Blocked).where(id: id, effect_started_at: nil)
                                            .update(status: Dto::JobStatus::Pending.serialize, available_at: Time.now, attempts: 0, last_error: nil) == 1
      end

      # Completes an uncertain job after its effect was verified out of band.
      sig { params(id: String).returns(T::Boolean) }
      def close_uncertain(id:)
        with_status(Dto::JobStatus::Uncertain).where(id: id).update(status: Dto::JobStatus::Complete.serialize, lease_token: nil, lease_expires_at: nil) == 1
      end

      # Completes a job, in any status, that a verified human reconciliation settled.
      sig { params(id: String).void }
      def close_reconciled(id:)
        Entities::Job.query.where(id: id).update(status: Dto::JobStatus::Complete.serialize, lease_token: nil, lease_expires_at: nil)
      end

      # True when a pending or blocked job of `kind` with no started effect has payload[field] == value.
      sig { params(kind: Dto::JobKind, field: String, value: String).returns(T::Boolean) }
      def unstarted?(kind:, field:, value:)
        candidates = Entities::Job.query.where(kind: kind.serialize, effect_started_at: nil,
                                               status: [Dto::JobStatus::Pending.serialize, Dto::JobStatus::Blocked.serialize])
        Entities::Job.resolve(candidates).any? { |job| job.payload[field] == value }
      end

      private

      sig { params(job: T.nilable(Entities::Job)).returns(T.nilable(Dto::JobSnapshot)) }
      def snapshot(job)
        return nil unless job

        Dto::JobSnapshot.new(id: job.id, status: job.status, lease_expires_at: job.lease_expires_at, effect_started_at: job.effect_started_at)
      end

      sig { params(status: Dto::JobStatus).returns(Sequel::Dataset) }
      def with_status(status) = Entities::Job.query.where(status: status.serialize)

      sig { params(id: String, token: String, now: Time).returns(Sequel::Dataset) }
      def live(id, token, now)
        with_status(Dto::JobStatus::Running).where(id: id, lease_token: token).where(Sequel[:jobs][:lease_expires_at] > now)
      end
    end
  end
end

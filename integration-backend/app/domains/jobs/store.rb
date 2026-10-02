# typed: strict
# frozen_string_literal: true

module Domains
  module Jobs
    class Store
      extend T::Sig

      BACKOFF = T.let([1, 5, 15, 60].freeze, T::Array[Integer])

      sig { params(kind: String, payload: Job::Payload, key: String, available_at: Time).returns(String) }
      def enqueue(kind:, payload:, key:, available_at: Time.now)
        id = SecureRandom.uuid
        job = begin
          Job.db.transaction(savepoint: true) do
            Job.create(id: id, kind: kind, payload: payload, dispatch_key: key, available_at: available_at)
          end
        rescue Sequel::UniqueConstraintViolation
          T.must(Job.find_by(dispatch_key: key))
        end
        raise ArgumentError, "Dispatch key reused with changed content" unless job.kind == kind && job.payload == payload

        job.id
      end

      sig { params(worker_id: String, now: Time).returns(T.nilable(Job)) }
      def claim(worker_id:, now: Time.now)
        Job.db.transaction do
          expired = Job.query.where(status: "running").where(Sequel[:jobs][:lease_expires_at] <= now)
          expired.exclude(effect_started_at: nil).update(status: "uncertain", last_error: "Expired after external effect began")
          expired.where(effect_started_at: nil, attempts: 5).update(status: "blocked", last_error: "Attempt budget exhausted")
          expired.where(effect_started_at: nil).exclude(attempts: 5).update(status: "pending", lease_token: nil)
          row = Job.query.where(status: "pending").where(Sequel[:jobs][:available_at] <= now).order(:available_at, :id).for_update.skip_locked.first
          return nil unless row

          job = T.must(Job.resolve([row]).first)
          Job.query.where(id: job.id).update(
            status: "running",
            worker_id: worker_id,
            lease_token: SecureRandom.uuid,
            lease_expires_at: now + 30,
            attempts: job.attempts + 1
          )
          T.must(Job.find_by(id: job.id))
        end
      end

      sig { params(id: String, lease_token: String, now: Time).returns(T::Boolean) }
      def complete(id:, lease_token:, now: Time.now) = live(id, lease_token, now).update(status: "complete", lease_token: nil, lease_expires_at: nil) == 1

      sig { params(id: String, lease_token: String, now: Time).returns(T::Boolean) }
      def heartbeat(id:, lease_token:, now: Time.now) = live(id, lease_token, now).update(lease_expires_at: now + 30) == 1

      sig { params(id: String, lease_token: String, now: Time).returns(T::Boolean) }
      def begin_effect(id:, lease_token:, now: Time.now) = live(id, lease_token, now).where(effect_started_at: nil).update(effect_started_at: now) == 1

      sig { params(id: String, lease_token: String, error: String, now: Time).returns(T::Boolean) }
      def retry(id:, lease_token:, error:, now: Time.now)
        Job.db.transaction do
          row = live(id, lease_token, now).for_update.first
          return false unless row

          job = T.must(Job.resolve([row]).first)
          status = job.effect_started_at ? "uncertain" : (job.attempts >= 5 ? "blocked" : "pending")
          Job.query.where(id: id).update(
            status: status,
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
        Job.db.transaction do
          row = live(id, lease_token, now).where(effect_started_at: nil).for_update.first
          return false unless row

          job = T.must(Job.resolve([row]).first)
          Job.query.where(id: job.id).update(status: "pending", lease_token: nil, lease_expires_at: nil,
                                              available_at: now + 2, attempts: [job.attempts - 1, 0].max, last_error: reason) == 1
        end
      end

      sig { params(id: String, lease_token: String, reason: String, now: Time).returns(T::Boolean) }
      def block(id:, lease_token:, reason:, now: Time.now)
        live(id, lease_token, now).update(status: "blocked", last_error: reason, lease_token: nil, lease_expires_at: nil) == 1
      end

      private

      sig { params(id: String, token: String, now: Time).returns(Sequel::Dataset) }
      def live(id, token, now) = Job.query.where(id: id, status: "running", lease_token: token).where(Sequel[:jobs][:lease_expires_at] > now)
    end
  end
end

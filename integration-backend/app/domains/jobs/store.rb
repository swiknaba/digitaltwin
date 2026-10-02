# frozen_string_literal: true

module Domains
  module Jobs
    class Store
      BACKOFF = [1, 5, 15, 60].freeze
      def initialize(db) = @db = db

      def enqueue(kind:, payload:, key:, available_at: Time.now)
        id = SecureRandom.uuid
        @db[:jobs].insert_conflict(target: :dispatch_key).insert(id: id, kind: kind, payload: Sequel.pg_jsonb(payload),
                                                                 dispatch_key: key, available_at: available_at)
        row = @db[:jobs][dispatch_key: key]
        raise ArgumentError,
              "Dispatch key reused with changed content" unless row[:kind] == kind && row[:payload] == payload

        row[:id]
      end

      def claim(worker_id:, now: Time.now)
        @db.transaction do
          expired = @db[:jobs].where(status: "running").where { lease_expires_at <= now }
          expired.exclude(effect_started_at: nil).update(status: "uncertain",
                                                         last_error: "Expired after external effect began")
          expired.where(effect_started_at: nil, attempts: 5).update(status: "blocked",
                                                                    last_error: "Attempt budget exhausted")
          expired.where(effect_started_at: nil).exclude(attempts: 5).update(status: "pending", lease_token: nil)
          row = @db[:jobs].where(status: "pending").where {
            available_at <= now
          }.order(:available_at, :id).for_update.skip_locked.first
          return nil unless row

          token = SecureRandom.uuid
          @db[:jobs].where(id: row[:id]).update(status: "running", worker_id: worker_id, lease_token: token,
                                                lease_expires_at: now + 30, attempts: row[:attempts] + 1)
          @db[:jobs][id: row[:id]]
        end
      end

      def complete(id:, lease_token:, now: Time.now)
        live(id, lease_token, now).update(status: "complete", lease_token: nil, lease_expires_at: nil) == 1
      end

      def heartbeat(id:, lease_token:, now: Time.now)
        live(id, lease_token, now).update(lease_expires_at: now + 30) == 1
      end

      def begin_effect(id:, lease_token:, now: Time.now)
        live(id, lease_token, now).where(effect_started_at: nil).update(effect_started_at: now) == 1
      end

      def retry(id:, lease_token:, error:, now: Time.now)
        @db.transaction do
          row = live(id, lease_token, now).for_update.first
          return false unless row

          status = row[:effect_started_at] ? "uncertain" : (row[:attempts] >= 5 ? "blocked" : "pending")
          @db[:jobs].where(id: id).update(status: status, lease_token: nil, lease_expires_at: nil,
                                          available_at: now + BACKOFF.fetch([row[:attempts] - 1, 3].min), last_error: error.to_s[0, 512])
          true
        end
      end

      def defer(id:, lease_token:, reason:, now: Time.now)
        live(id, lease_token, now).where(effect_started_at: nil).update(status: "pending", lease_token: nil,
                                                                        lease_expires_at: nil, available_at: now + 2, attempts: Sequel.lit("GREATEST(attempts - 1, 0)"), last_error: reason) == 1
      end

      def block(id:, lease_token:, reason:, now: Time.now)
        live(id, lease_token, now).update(status: "blocked", last_error: reason, lease_token: nil,
                                          lease_expires_at: nil) == 1
      end
      private def live(id, token, now)
        @db[:jobs].where(id: id, status: "running", lease_token: token).where { lease_expires_at > now }
      end
    end
  end
end

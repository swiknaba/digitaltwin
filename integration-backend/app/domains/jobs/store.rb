# typed: strict
# frozen_string_literal: true

require "json"

module Domains
  module Jobs
    # The Sequel boundary validates a row before it reaches a handler.
    class Store
      extend T::Sig

      BACKOFF = T.let([1, 5, 15, 60].freeze, T::Array[Integer])
      Payload = T.type_alias { T::Hash[String, Object] }

      class Job < T::Struct
        extend T::Sig

        const :id, String
        const :kind, String
        const :payload, Payload
        const :dispatch_key, String
        const :status, String
        const :worker_id, T.nilable(String)
        const :lease_token, T.nilable(String)
        const :lease_expires_at, T.nilable(Time)
        const :attempts, Integer
        const :available_at, Time
        const :effect_started_at, T.nilable(Time)
        const :last_error, T.nilable(String)

        # Keeps existing handlers working while they move to named fields.
        sig { params(key: Symbol).returns(T.nilable(Object)) }
        def [](key)
          { id: id, kind: kind, payload: payload, dispatch_key: dispatch_key, status: status,
            worker_id: worker_id, lease_token: lease_token, lease_expires_at: lease_expires_at,
            attempts: attempts, available_at: available_at, effect_started_at: effect_started_at,
            last_error: last_error }[key]
        end
      end

      sig { params(db: Sequel::Database).void }
      def initialize(db)
        @db = T.let(db, Sequel::Database)
      end

      sig { params(kind: String, payload: Payload, key: String, available_at: Time).returns(String) }
      def enqueue(kind:, payload:, key:, available_at: Time.now)
        id = SecureRandom.uuid
        content = payload!(payload)
        @db[:jobs].insert_conflict(target: :dispatch_key).insert(id: id, kind: kind, payload: jsonb(content), dispatch_key: key, available_at: available_at)
        job = job_from(@db[:jobs][dispatch_key: key])
        raise ArgumentError, "Dispatch key reused with changed content" unless job.kind == kind && job.payload == content

        job.id
      end

      sig { params(worker_id: String, now: Time).returns(T.nilable(Job)) }
      def claim(worker_id:, now: Time.now)
        @db.transaction do
          expired = @db[:jobs].where(status: "running").where(Sequel[:jobs][:lease_expires_at] <= now)
          expired.exclude(effect_started_at: nil).update(status: "uncertain", last_error: "Expired after external effect began")
          expired.where(effect_started_at: nil, attempts: 5).update(status: "blocked", last_error: "Attempt budget exhausted")
          expired.where(effect_started_at: nil).exclude(attempts: 5).update(status: "pending", lease_token: nil)
          row = @db[:jobs].where(status: "pending").where(Sequel[:jobs][:available_at] <= now).order(:available_at, :id).for_update.skip_locked.first
          return nil unless row

          job = job_from(row)
          @db[:jobs].where(id: job.id).update(
            status: "running",
            worker_id: worker_id,
            lease_token: SecureRandom.uuid,
            lease_expires_at: now + 30,
            attempts: job.attempts + 1
          )
          job_from(@db[:jobs][id: job.id])
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
        @db.transaction do
          row = live(id, lease_token, now).for_update.first
          return false unless row

          job = job_from(row)
          status = job.effect_started_at ? "uncertain" : (job.attempts >= 5 ? "blocked" : "pending")
          @db[:jobs].where(id: id).update(
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
        live(id, lease_token, now).where(effect_started_at: nil).update(
          status: "pending",
          lease_token: nil,
          lease_expires_at: nil,
          available_at: now + 2,
          attempts: Sequel.lit("GREATEST(attempts - 1, 0)"),
          last_error: reason
        ) == 1
      end

      sig { params(id: String, lease_token: String, reason: String, now: Time).returns(T::Boolean) }
      def block(id:, lease_token:, reason:, now: Time.now)
        live(id, lease_token, now).update(status: "blocked", last_error: reason, lease_token: nil, lease_expires_at: nil) == 1
      end

      private

      sig { params(id: String, token: String, now: Time).returns(Sequel::Dataset) }
      def live(id, token, now) = @db[:jobs].where(id: id, status: "running", lease_token: token).where(Sequel[:jobs][:lease_expires_at] > now)

      sig { params(payload: Payload).returns(Sequel::SQL::Expression) }
      def jsonb(payload)
        Sequel.lit("?::jsonb", JSON.generate(payload))
      end

      sig { params(row: Object).returns(Job) }
      def job_from(row)
        raise IOError, "Invalid durable job record" unless row.is_a?(Hash)

        Job.new(id: string!(row, :id), kind: string!(row, :kind), payload: payload!(row.fetch(:payload) { raise IOError, "Invalid durable job record" }),
                dispatch_key: string!(row, :dispatch_key), status: string!(row, :status), worker_id: optional_string(row, :worker_id),
                lease_token: optional_string(row, :lease_token), lease_expires_at: optional_time(row, :lease_expires_at), attempts: integer!(row, :attempts),
                available_at: time!(row, :available_at), effect_started_at: optional_time(row, :effect_started_at), last_error: optional_string(row, :last_error))
      end

      # Sequel returns JSONB through a BasicObject-backed Hash wrapper. Accept
      # the external boundary's root object, then prove it is a Hash below.
      sig { params(value: BasicObject).returns(Payload) }
      def payload!(value)
        payload_hash = Hash.try_convert(value)
        raise IOError, "Invalid durable job payload" unless payload_hash

        payload = T.let({}, Payload)
        payload_hash.each do |key, item|
          raise IOError, "Invalid durable job payload" unless key.is_a?(String)

          payload[key] = json_value!(item)
        end
        payload
      end

      sig { params(value: Object).returns(Object) }
      def json_value!(value)
        case value
        when String, Integer, Float, TrueClass, FalseClass, NilClass then value
        when Array then value.map { |item| json_value!(item) }
        when Hash then payload!(value)
        else raise IOError, "Invalid durable job payload"
        end
      end

      sig { params(row: T::Hash[Object, Object], key: Symbol).returns(String) }
      def string!(row, key)
        value = row.fetch(key) { raise IOError, "Invalid durable job record" }
        raise IOError, "Invalid durable job record" unless value.is_a?(String)

        value
      end

      sig { params(row: T::Hash[Object, Object], key: Symbol).returns(T.nilable(String)) }
      def optional_string(row, key)
        value = row.fetch(key) { return nil }
        raise IOError, "Invalid durable job record" unless value.nil? || value.is_a?(String)

        value
      end

      sig { params(row: T::Hash[Object, Object], key: Symbol).returns(Integer) }
      def integer!(row, key)
        value = row.fetch(key) { raise IOError, "Invalid durable job record" }
        raise IOError, "Invalid durable job record" unless value.is_a?(Integer)

        value
      end

      sig { params(row: T::Hash[Object, Object], key: Symbol).returns(Time) }
      def time!(row, key)
        value = row.fetch(key) { raise IOError, "Invalid durable job record" }
        raise IOError, "Invalid durable job record" unless value.is_a?(Time)

        value
      end

      sig { params(row: T::Hash[Object, Object], key: Symbol).returns(T.nilable(Time)) }
      def optional_time(row, key)
        value = row.fetch(key) { return nil }
        raise IOError, "Invalid durable job record" unless value.nil? || value.is_a?(Time)

        value
      end
    end
  end
end

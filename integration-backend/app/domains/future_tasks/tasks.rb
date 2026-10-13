# typed: strict
# frozen_string_literal: true

require "time"
require "tzinfo"

module Domains
  module FutureTasks
    # Durable one-time Commander check-ins. The service owns every task and
    # execution transition; callers never enqueue queue rows directly.
    class Tasks
      extend T::Sig

      Kind = Platform::Jobs::Dto::JobKind
      TaskState = Dto::TaskState
      ExecutionState = Dto::ExecutionState

      sig { params(jobs: Platform::Jobs::Store).void }
      def initialize(jobs: Platform::Jobs::Store.new)
        @jobs = jobs
      end

      sig { params(actor_id: String, idempotency_key: String, text: String, due_at: Time, timezone: String, local_time: String, references: T::Array[String], origin: String, now: Time).returns(Dto::TaskView) }
      def create(actor_id:, idempotency_key:, text:, due_at:, timezone:, local_time:, references: [], origin: "commander", now: Time.now)
        digest = Digest::SHA256.hexdigest([origin, text.strip, due_at.utc.iso8601, timezone, local_time, references.sort.join("\u0000")].join("\u0000"))
        existing = tasks.where(actor_id:, idempotency_key:).first
        return view(existing) if existing && existing.fetch(:idempotency_digest) == digest

        raise ArgumentError, "Idempotency key reused with changed task" if existing

        validate_create!(actor_id:, origin:, idempotency_key:, text:, due_at:, timezone:, local_time:, references:, now:)

        task_id = SecureRandom.uuid
        execution_id = SecureRandom.uuid
        delivery_key = SecureRandom.uuid
        database.transaction do
          dispatch_key = "future-task:#{task_id}:1"
          @jobs.enqueue(kind: Kind::FutureTaskDue, payload: Dto::DueJob.new(execution_id:), dispatch_key:, available_at: due_at)
          job = T.must(@jobs.find_by_key(dispatch_key:))
          tasks.insert(id: task_id, actor_id:, origin:, target: "commander", text: text.strip, references: Sequel.pg_jsonb(references), timezone:, local_time:,
                       due_at:, version: 1, state: TaskState::Scheduled.serialize, idempotency_key:, idempotency_digest: digest, created_at: now, updated_at: now)
          executions.insert(id: execution_id, task_id:, generation: 1, delivery_key:, job_id: job.id, state: ExecutionState::Queued.serialize, created_at: now, updated_at: now)
        end
        T.must(find(actor_id:, id: task_id, origin:))
      rescue Sequel::UniqueConstraintViolation
        existing = tasks.where(actor_id:, idempotency_key:).first
        return view(existing) if existing && existing.fetch(:idempotency_digest) == digest

        raise ArgumentError, "Idempotency key reused with changed task"
      end

      sig { params(actor_id: String, id: String, origin: T.nilable(String)).returns(T.nilable(Dto::TaskView)) }
      def find(actor_id:, id:, origin: nil)
        query = tasks.where(id:, actor_id:)
        query = query.where(origin:) if origin
        row = query.first
        row ? view(row) : nil
      end

      sig { params(actor_id: String, cursor: T.nilable(String), limit: Integer).returns(Dto::TaskPage) }
      def list(actor_id:, cursor: nil, limit: 50)
        raise ArgumentError, "Task page limit is invalid" unless limit.between?(1, 100)
        raise ArgumentError, "Task cursor is invalid" if cursor && cursor.empty?

        query = tasks.where(actor_id:)
        query = after_cursor(query, cursor) if cursor
        rows = query.order(:created_at, :id).limit(limit + 1).all
        next_cursor = rows.length > limit ? cursor_for(rows.fetch(limit - 1)) : nil
        Dto::TaskPage.new(items: rows.first(limit).map { |row| view(row) }, next_cursor:)
      end

      sig { params(actor_id: String, id: String, expected_version: Integer, text: T.nilable(String), due_at: T.nilable(Time), timezone: T.nilable(String), local_time: T.nilable(String), origin: T.nilable(String), now: Time).returns(Dto::TaskView) }
      def update(actor_id:, id:, expected_version:, text: nil, due_at: nil, timezone: nil, local_time: nil, origin: nil, now: Time.now)
        database.transaction do
          task = locked_task(actor_id:, id:, origin:)
          require_scheduled!(task, expected_version:)
          next_text = text ? bounded_text(text) : task.fetch(:text)
          next_due_at = due_at || task.fetch(:due_at)
          next_timezone = timezone || task.fetch(:timezone)
          next_local_time = local_time || task.fetch(:local_time)
          validate_timing!(due_at: next_due_at, timezone: next_timezone, local_time: next_local_time, now:)
          stale_current_execution(task.fetch(:id), task.fetch(:version), now)
          version = task.fetch(:version) + 1
          create_generation(task_id: task.fetch(:id), generation: version, due_at: next_due_at, now:)
          tasks.where(id: task.fetch(:id)).update(
            text: next_text, due_at: next_due_at, timezone: next_timezone, local_time: next_local_time,
            version:, updated_at: now
          )
          T.must(find(actor_id:, id:, origin:))
        end
      end

      sig { params(actor_id: String, id: String, expected_version: Integer, origin: T.nilable(String), now: Time).returns(Dto::TaskView) }
      def cancel(actor_id:, id:, expected_version:, origin: nil, now: Time.now)
        database.transaction do
          task = locked_task(actor_id:, id:, origin:)
          require_scheduled!(task, expected_version:)
          stale_current_execution(task.fetch(:id), task.fetch(:version), now)
          tasks.where(id: task.fetch(:id)).update(state: TaskState::Canceled.serialize, version: expected_version + 1, updated_at: now)
          T.must(find(actor_id:, id:, origin:))
        end
      end

      sig { params(execution_id: String, lease: Platform::Jobs::Lease, gateway: Adapters::CommanderBridge::Gateway, now: Time).returns(Platform::Jobs::Dto::Decision) }
      def deliver(execution_id:, lease:, gateway:, now: Time.now)
        execution = database.transaction do
          row = executions.where(id: execution_id).for_update.first
          return Platform::Jobs::Dto::Decision.complete unless row && row.fetch(:state) == ExecutionState::Queued.serialize

          task = tasks.where(id: row.fetch(:task_id)).for_update.first
          unless task && task.fetch(:state) == TaskState::Scheduled.serialize && task.fetch(:version) == row.fetch(:generation)
            stale(row, now)
            return Platform::Jobs::Dto::Decision.complete
          end

          executions.where(id: execution_id).update(state: ExecutionState::Claimed.serialize, claimed_at: now, updated_at: now)
          tasks.where(id: task.fetch(:id)).update(state: TaskState::Running.serialize, updated_at: now)
          [row, task]
        end
        return Platform::Jobs::Dto::Decision.complete unless execution

        row, task = execution
        unless lease.begin_effect
          mark_uncertain(execution_id:, now:, reason: "lease lost before Commander delivery")
          return Platform::Jobs::Dto::Decision.complete
        end
        database.transaction { executions.where(id: execution_id).update(state: ExecutionState::Delivering.serialize, updated_at: now) }
        receipt = gateway.deliver(task_id: task.fetch(:id), text: task.fetch(:text), references: json_array(task.fetch(:references)), due_at: task.fetch(:due_at),
                                  timezone: task.fetch(:timezone), delivery_key: row.fetch(:delivery_key))
        mark_delivered(execution_id:, receipt:, now:)
        Platform::Jobs::Dto::Decision.complete
      rescue StandardError => error
        mark_uncertain(execution_id:, now:, reason: error.message)
        Platform::Jobs::Dto::Decision.complete
      end

      sig { params(actor_id: String, id: String, expected_version: Integer, disposition_key: String, outcome: String, due_at: T.nilable(Time), timezone: T.nilable(String), local_time: T.nilable(String), origin: T.nilable(String), now: Time).returns(Dto::TaskView) }
      def record_disposition(actor_id:, id:, expected_version:, disposition_key:, outcome:, due_at: nil, timezone: nil, local_time: nil, origin: nil, now: Time.now)
        database.transaction do
          task = locked_task(actor_id:, id:, origin:)
          digest = disposition_digest(outcome:, due_at:, timezone:, local_time:)
          existing = dispositions.where(task_id: task.fetch(:id), idempotency_key: disposition_key).first
          return T.must(find(actor_id:, id:, origin:)) if existing && existing.fetch(:idempotency_digest) == digest
          raise ArgumentError, "Disposition key reused with changed body" if existing

          raise ArgumentError, "Task version is stale" unless task.fetch(:version) == expected_version
          raise ArgumentError, "Task is not awaiting a Commander reply" unless task.fetch(:state) == TaskState::AwaitingDisposition.serialize
          raise ArgumentError, "Unsupported disposition" unless %w[assessed project_work_requested user_canceled rescheduled].include?(outcome)

          next_state = outcome == "user_canceled" ? TaskState::Canceled : TaskState::Completed
          if outcome == "rescheduled"
            raise ArgumentError, "Reschedule timing is required" unless due_at && timezone && local_time

            validate_timing!(due_at:, timezone:, local_time:, now:)
            version = expected_version + 1
            create_generation(task_id: task.fetch(:id), generation: version, due_at:, now:)
            tasks.where(id: task.fetch(:id)).update(state: TaskState::Scheduled.serialize, version:, due_at:, timezone:, local_time:, updated_at: now)
          else
            tasks.where(id: task.fetch(:id)).update(state: next_state.serialize, updated_at: now)
          end
          dispositions.insert(id: SecureRandom.uuid, task_id: task.fetch(:id), execution_id: current_execution(task.fetch(:id), expected_version).fetch(:id),
                              idempotency_key: disposition_key, idempotency_digest: digest, outcome:, created_at: now)
          T.must(find(actor_id:, id:, origin:))
        end
      end

      sig { params(execution_id: String, receipt: Dto::DeliveryReceipt, now: Time).void }
      def mark_delivered(execution_id:, receipt:, now: Time.now)
        database.transaction do
          execution = executions.where(id: execution_id).for_update.first
          raise KeyError, "Future task execution not found" unless execution

          return unless [ExecutionState::Delivering.serialize, ExecutionState::Uncertain.serialize].include?(execution.fetch(:state))

          executions.where(id: execution_id).update(state: ExecutionState::Delivered.serialize, receipt: Sequel.pg_jsonb(receipt.serialize), delivered_at: now, updated_at: now)
          tasks.where(id: execution.fetch(:task_id)).update(state: TaskState::AwaitingDisposition.serialize, updated_at: now)
          attempts.insert(id: SecureRandom.uuid, execution_id:, sequence: next_attempt_sequence(execution_id), state: "delivered", detail: Sequel.pg_jsonb(receipt.serialize), created_at: now)
        end
      end

      sig { params(execution_id: String, reason: String, now: Time).void }
      def mark_uncertain(execution_id:, reason:, now: Time.now)
        database.transaction do
          execution = executions.where(id: execution_id).for_update.first
          return unless execution

          executions.where(id: execution_id).update(state: ExecutionState::Uncertain.serialize, updated_at: now)
          tasks.where(id: execution.fetch(:task_id)).update(state: TaskState::Uncertain.serialize, updated_at: now)
          attempts.insert(id: SecureRandom.uuid, execution_id:, sequence: next_attempt_sequence(execution_id), state: "uncertain", detail: Sequel.pg_jsonb({ "reason" => reason[0, 256] }), created_at: now)
          enqueue_reconcile(execution_id:, now:)
        end
      end

      # Reconciliation queries/retries only the existing delivery key. A receipt
      # settles it; another unavailable result leaves the record visibly uncertain.
      sig { params(execution_id: String, lease: Platform::Jobs::Lease, gateway: Adapters::CommanderBridge::Gateway, now: Time).returns(Platform::Jobs::Dto::Decision) }
      def reconcile(execution_id:, lease:, gateway:, now: Time.now)
        execution, task = database.transaction do
          row = executions.where(id: execution_id).for_update.first
          return Platform::Jobs::Dto::Decision.complete unless row && row.fetch(:state) == ExecutionState::Uncertain.serialize

          task_row = tasks.where(id: row.fetch(:task_id)).for_update.first
          return Platform::Jobs::Dto::Decision.complete unless task_row && task_row.fetch(:state) == TaskState::Uncertain.serialize

          [row, task_row]
        end
        return Platform::Jobs::Dto::Decision.complete unless lease.begin_effect

        resolution = gateway.reconcile(delivery_key: execution.fetch(:delivery_key))
        if resolution.receipt
          mark_delivered(execution_id:, receipt: T.must(resolution.receipt), now:)
        elsif resolution.terminal_failure
          mark_failed(execution_id:, reason: T.must(resolution.terminal_failure), now:)
        else
          receipt = gateway.deliver(task_id: task.fetch(:id), text: task.fetch(:text), references: json_array(task.fetch(:references)), due_at: task.fetch(:due_at),
                                    timezone: task.fetch(:timezone), delivery_key: execution.fetch(:delivery_key))
          mark_delivered(execution_id:, receipt:, now:)
        end
        Platform::Jobs::Dto::Decision.complete
      rescue StandardError => error
        mark_uncertain(execution_id:, now:, reason: error.message)
        Platform::Jobs::Dto::Decision.complete
      end

      # An owner-capability caller chooses only a final, recorded resolution. It
      # cannot fabricate a receipt or create another delivery key.
      sig { params(actor_id: String, id: String, expected_version: Integer, resolution_key: String, outcome: String, reason: T.nilable(String), origin: T.nilable(String), now: Time).returns(Dto::TaskView) }
      def resolve_uncertain(actor_id:, id:, expected_version:, resolution_key:, outcome:, reason: nil, origin: nil, now: Time.now)
        database.transaction do
          task = locked_task(actor_id:, id:, origin:)
          digest = resolution_digest(outcome:, reason:)
          existing = dispositions.where(task_id: task.fetch(:id), idempotency_key: resolution_key).first
          return T.must(find(actor_id:, id:, origin:)) if existing && existing.fetch(:idempotency_digest) == digest
          raise ArgumentError, "Resolution key reused with changed body" if existing

          raise ArgumentError, "Task version is stale" unless task.fetch(:version) == expected_version
          raise ArgumentError, "Task is not uncertain" unless task.fetch(:state) == TaskState::Uncertain.serialize
          raise ArgumentError, "Resolution must be failed or canceled" unless %w[failed canceled].include?(outcome)

          execution = current_execution(task.fetch(:id), expected_version)
          state = outcome == "failed" ? TaskState::Failed : TaskState::Canceled
          execution_state = outcome == "failed" ? ExecutionState::Failed : ExecutionState::Uncertain
          executions.where(id: execution.fetch(:id)).update(state: execution_state.serialize, updated_at: now)
          tasks.where(id: task.fetch(:id)).update(state: state.serialize, updated_at: now)
          attempts.insert(id: SecureRandom.uuid, execution_id: execution.fetch(:id), sequence: next_attempt_sequence(execution.fetch(:id)), state: outcome,
                          detail: Sequel.pg_jsonb({ "reason" => (reason || "owner resolution")[0, 256] }), created_at: now)
          dispositions.insert(id: SecureRandom.uuid, task_id: task.fetch(:id), execution_id: execution.fetch(:id), idempotency_key: resolution_key,
                              idempotency_digest: digest, outcome: "owner_#{outcome}", created_at: now)
          T.must(find(actor_id:, id:, origin:))
        end
      end

      sig { params(execution_id: String, reason: String, now: Time).void }
      def mark_failed(execution_id:, reason:, now: Time.now)
        database.transaction do
          execution = executions.where(id: execution_id).for_update.first
          return unless execution

          executions.where(id: execution_id).update(state: ExecutionState::Failed.serialize, updated_at: now)
          tasks.where(id: execution.fetch(:task_id)).update(state: TaskState::Failed.serialize, updated_at: now)
          attempts.insert(id: SecureRandom.uuid, execution_id:, sequence: next_attempt_sequence(execution_id), state: "failed", detail: Sequel.pg_jsonb({ "reason" => reason[0, 256] }), created_at: now)
        end
      end

      sig { returns(Sequel::Database) }
      private def database = Kirei::App.raw_db_connection

      sig { returns(Sequel::Dataset) }
      private def tasks = database[:future_tasks]

      sig { returns(Sequel::Dataset) }
      private def executions = database[:future_task_executions]

      sig { returns(Sequel::Dataset) }
      private def attempts = database[:future_task_delivery_attempts]

      sig { returns(Sequel::Dataset) }
      private def dispositions = database[:future_task_dispositions]

      sig { params(actor_id: String, id: String, origin: T.nilable(String)).returns(T::Hash[Symbol, T.untyped]) }
      private def locked_task(actor_id:, id:, origin: nil)
        query = tasks.where(id:, actor_id:)
        query = query.where(origin:) if origin
        task = query.for_update.first
        raise KeyError, "Future task not found" unless task

        task
      end

      sig { params(task: T::Hash[Symbol, T.untyped], expected_version: Integer).void }
      private def require_scheduled!(task, expected_version:)
        raise ArgumentError, "Task version is stale" unless task.fetch(:version) == expected_version
        raise ArgumentError, "Task has already started" unless task.fetch(:state) == TaskState::Scheduled.serialize
      end

      sig { params(task_id: String, generation: Integer, due_at: Time, now: Time).void }
      private def create_generation(task_id:, generation:, due_at:, now:)
        execution_id = SecureRandom.uuid
        dispatch_key = "future-task:#{task_id}:#{generation}"
        @jobs.enqueue(kind: Kind::FutureTaskDue, payload: Dto::DueJob.new(execution_id:), dispatch_key:, available_at: due_at)
        job = T.must(@jobs.find_by_key(dispatch_key:))
        executions.insert(id: execution_id, task_id:, generation:, delivery_key: SecureRandom.uuid, job_id: job.id, state: ExecutionState::Queued.serialize, created_at: now, updated_at: now)
      end

      sig { params(task_id: String, generation: Integer, now: Time).void }
      private def stale_current_execution(task_id, generation, now)
        executions.where(task_id:, generation:, state: [ExecutionState::Queued.serialize, ExecutionState::Claimed.serialize]).update(state: ExecutionState::Stale.serialize, updated_at: now)
      end

      sig { params(row: T::Hash[Symbol, T.untyped], now: Time).returns(NilClass) }
      private def stale(row, now)
        executions.where(id: row.fetch(:id)).update(state: ExecutionState::Stale.serialize, updated_at: now)
        nil
      end

      sig { params(task_id: String, generation: T.nilable(Integer)).returns(T::Hash[Symbol, T.untyped]) }
      private def current_execution(task_id, generation = nil)
        query = executions.where(task_id:)
        query = query.where(generation:) if generation
        T.let(query.order(Sequel.desc(:generation)).first, T::Hash[Symbol, T.untyped])
      end

      sig { params(execution_id: String).returns(Integer) }
      private def next_attempt_sequence(execution_id) = attempts.where(execution_id:).count + 1

      sig { params(row: T::Hash[Symbol, T.untyped]).returns(Dto::TaskView) }
      private def view(row)
        execution = current_execution(row.fetch(:id))
        disposition = dispositions.where(task_id: row.fetch(:id)).order(Sequel.desc(:created_at)).first
        receipt = execution[:receipt]
        rendered_receipt = if receipt
                             Dto::DeliveryReceipt.new(delivery_key: String(receipt.fetch("delivery_key")), commander_item_id: String(receipt.fetch("commander_item_id")))
                           end
        Dto::TaskView.new(
          id: row.fetch(:id), created_at: row.fetch(:created_at), actor_id: row.fetch(:actor_id), origin: row.fetch(:origin), text: row.fetch(:text), references: json_array(row.fetch(:references)), timezone: row.fetch(:timezone),
          local_time: row.fetch(:local_time), due_at: row.fetch(:due_at), version: row.fetch(:version), state: TaskState.deserialize(row.fetch(:state)), outcome: disposition&.fetch(:outcome),
          execution_id: execution.fetch(:id), delivery_key: execution.fetch(:delivery_key), receipt: rendered_receipt
        )
      end

      sig { params(value: T.untyped).returns(T::Array[String]) }
      private def json_array(value) = Array(value).map { |item| String(item) }

      sig { params(query: Sequel::Dataset, cursor: String).returns(Sequel::Dataset) }
      private def after_cursor(query, cursor)
        created_at, id = decode_cursor(cursor)
        table = Sequel[:future_tasks]
        query.where((table[:created_at] > created_at) | (Sequel.expr({ table[:created_at] => created_at }) & (table[:id] > id)))
      end

      sig { params(row: T::Hash[Symbol, T.untyped]).returns(String) }
      private def cursor_for(row)
        [row.fetch(:created_at).utc.iso8601(6), row.fetch(:id)].join("\u0000").unpack1("H*")
      end

      sig { params(cursor: String).returns([Time, String]) }
      private def decode_cursor(cursor)
        raise ArgumentError, "Task cursor is invalid" unless cursor.match?(/\A[0-9a-f]+\z/) && cursor.length.even?

        encoded = [cursor].pack("H*")
        created_at, id = encoded.split("\u0000", 2)
        raise ArgumentError, "Task cursor is invalid" unless created_at && id && !id.empty?

        [Time.iso8601(created_at), id]
      rescue ArgumentError
        raise ArgumentError, "Task cursor is invalid"
      end

      sig { params(outcome: String, due_at: T.nilable(Time), timezone: T.nilable(String), local_time: T.nilable(String)).returns(String) }
      private def disposition_digest(outcome:, due_at:, timezone:, local_time:)
        Digest::SHA256.hexdigest([outcome, due_at&.utc&.iso8601, timezone, local_time].join("\u0000"))
      end

      sig { params(outcome: String, reason: T.nilable(String)).returns(String) }
      private def resolution_digest(outcome:, reason:)
        Digest::SHA256.hexdigest([outcome, reason].join("\u0000"))
      end

      sig { params(actor_id: String, origin: String, idempotency_key: String, text: String, due_at: Time, timezone: String, local_time: String, references: T::Array[String], now: Time).void }
      private def validate_create!(actor_id:, origin:, idempotency_key:, text:, due_at:, timezone:, local_time:, references:, now:)
        raise ArgumentError, "Actor is required" if actor_id.empty?
        raise ArgumentError, "Commander conversation origin is required" if origin.empty?
        raise ArgumentError, "Idempotency key is required" if idempotency_key.empty? || idempotency_key.length > 128

        bounded_text(text)
        raise ArgumentError, "Too many references" if references.length > 16 || references.any? { |reference| reference.length > 512 }

        validate_timing!(due_at:, timezone:, local_time:, now:)
      end

      sig { params(text: String).returns(String) }
      private def bounded_text(text)
        normalized = text.strip
        raise ArgumentError, "Task text is required" if normalized.empty? || normalized.length > 4000

        normalized
      end

      sig { params(due_at: Time, timezone: String, local_time: String, now: Time).void }
      private def validate_timing!(due_at:, timezone:, local_time:, now:)
        raise ArgumentError, "Future task must be in the future" unless due_at > now

        raise ArgumentError, "Local time must include an explicit UTC offset" unless /(?:Z|[+-]\d{2}:\d{2})\z/.match?(local_time)

        submitted = Time.iso8601(local_time)
        zone = TZInfo::Timezone.get(timezone)
        wall = Time.utc(submitted.year, submitted.month, submitted.day, submitted.hour, submitted.min, submitted.sec)
        periods = zone.periods_for_local(wall)
        raise ArgumentError, "Local time falls in a daylight-saving gap" if periods.empty?
        raise ArgumentError, "Local time offset does not match timezone" unless periods.any? { |period| period.utc_total_offset == submitted.utc_offset }
        raise ArgumentError, "Canonical due time does not match local time" unless due_at.utc.to_i == submitted.utc.to_i
      rescue TZInfo::InvalidTimezoneIdentifier
        raise ArgumentError, "Timezone is invalid"
      rescue ArgumentError
        raise ArgumentError, "Local time is invalid" unless local_time.is_a?(String)

        raise
      end

      sig { params(execution_id: String, now: Time).void }
      private def enqueue_reconcile(execution_id:, now:)
        dispatch_key = "future-task-reconcile:#{execution_id}"
        @jobs.enqueue(kind: Kind::FutureTaskReconcile, payload: Dto::ReconcileJob.new(execution_id:), dispatch_key:, available_at: now + 60)
      end
    end
  end
end

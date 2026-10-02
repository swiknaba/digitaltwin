# typed: strict
# frozen_string_literal: true

module Domains
  module Mattermost
    # Persists verified deliveries before asking the worker to perform any work.
    class Router
      extend T::Sig

      sig do
        params(db: Sequel::Database, agent_handle: String, worker_handle: String,
               master_channel_id: T.nilable(String)).void
      end
      def initialize(db, agent_handle: ENV.fetch("AGENT_HANDLE", "agent"),
                     worker_handle: ENV.fetch("WORKER_HANDLE", "worker"),
                     master_channel_id: ENV["MASTER_CHANNEL_ID"])
        @db = T.let(db, Sequel::Database)
        @agent = T.let(valid_handle!(agent_handle), String)
        @worker = T.let(valid_handle!(worker_handle), String)
        @master_channel = T.let(master_channel_id, T.nilable(String))
      end

      sig { params(delivery: VerifiedDelivery).returns(Domains::Workflows::Entities::Outcome) }
      def ingest(delivery:)
        @db.transaction do
          inbox_id = persist_inbox(delivery)
          return result("accepted", "Duplicate delivery") unless inbox_id
          return result("accepted", "Revision recorded without dispatch") unless delivery.event_kind == "posted"

          workflow = workflow_for(delivery)
          command = command_for(delivery.body)
          return result("rejected", "Human action requires verified member") if command && (!delivery.actor.member || delivery.actor.bot)

          if master_prompt?(delivery)
            queue(Platform::Jobs::Dto::JobKind::MasterPrompt, delivery, inbox_id)
          elsif command == "start"
            return result("rejected", "Start requires a new thread root") unless delivery.root_post && workflow.nil?

            queue(Platform::Jobs::Dto::JobKind::WorkflowStart, delivery, inbox_id)
          elsif workflow && dispatch_suppressed?(workflow) && command.nil?
            queue_message(workflow, inbox_id)
            Outbox.new.enqueue(channel_id: delivery.channel_id, thread_id: delivery.thread_id, bot: "worker", role: "writer",
                               body: "Message queued; delivery waits for review or pause completion.", key: "queued:#{inbox_id}")
            result("accepted", "Queued under dispatch suppression")
          elsif workflow && !delivery.actor.bot && !closed?(workflow)
            queue(Platform::Jobs::Dto::JobKind.deserialize(command ? "workflow.#{command}" : "workflow.prompt"), delivery, inbox_id, workflow: workflow)
          else
            result("accepted", "No activated workflow")
          end
        end
      end

      private

      sig { params(handle: String).returns(String) }
      def valid_handle!(handle)
        raise ArgumentError, "Invalid bot handle" unless handle.match?(/\A[a-z0-9_.-]+\z/)

        handle
      end

      sig { params(delivery: VerifiedDelivery).returns(T.nilable(Integer)) }
      def persist_inbox(delivery)
        record = { channel_id: delivery.channel_id, post_id: delivery.post_id, event_kind: delivery.event_kind,
                   post_revision: delivery.post_revision }
        id = @db[:inbox].insert_conflict(target: record.keys).insert(**record, thread_id: delivery.thread_id,
                                                                               user_id: delivery.actor.user_id,
                                                                               verified_delivery: Sequel.pg_jsonb(delivery.serialize))
        return id if id.is_a?(Integer)

        nil
      end

      sig { params(delivery: VerifiedDelivery).returns(T.nilable(Domains::Workflows::Workflow)) }
      def workflow_for(delivery)
        Domains::Workflows::Workflow.find_by(channel_id: delivery.channel_id, thread_id: delivery.thread_id, archived_at: nil)
      end

      sig { params(body: String).returns(T.nilable(String)) }
      def command_for(body)
        body[/\A@#{Regexp.escape(@worker)}\s+(start|approve|pause|resume|finish|cancel)\b/, 1]
      end

      sig { params(delivery: VerifiedDelivery).returns(T::Boolean) }
      def master_prompt?(delivery)
        (delivery.channel_id == @master_channel || delivery.body.match?(/(?:\A|\s)@#{Regexp.escape(@agent)}\b/)) &&
          delivery.actor.member && !delivery.actor.bot
      end

      sig { params(workflow: T.nilable(Domains::Workflows::Workflow)).returns(T::Boolean) }
      def dispatch_suppressed?(workflow)
        return false unless workflow

        phase = workflow.phase
        phase == "paused" || phase.end_with?("_review")
      end

      sig { params(workflow: Domains::Workflows::Workflow).returns(T::Boolean) }
      def closed?(workflow)
        %w[closed cancelled].include?(workflow.phase)
      end

      sig { params(workflow: Domains::Workflows::Workflow, inbox_id: Integer).void }
      def queue_message(workflow, inbox_id)
        @db[:queued_messages].insert(workflow_id: workflow.id, inbox_id: inbox_id, workflow_version: workflow.version)
      end

      sig do
        params(kind: Platform::Jobs::Dto::JobKind, delivery: VerifiedDelivery, inbox_id: Integer,
               workflow: T.nilable(Domains::Workflows::Workflow)).returns(Domains::Workflows::Entities::Outcome)
      end
      def queue(kind, delivery, inbox_id, workflow: nil)
        payload = Domains::Commander::Dto::InboxDispatchJob.new(inbox_id: inbox_id, channel_id: delivery.channel_id, thread_id: delivery.thread_id,
                                                                workflow_id: workflow&.id, expected_version: workflow&.version)
        Platform::Jobs::Store.new.enqueue(kind: kind, payload: payload, dispatch_key: "inbox:#{inbox_id}:#{kind.serialize}")
        result("blocked", "Recorded durably; live Task 1 workflow dispatch is gated")
      end

      sig { params(status: String, reason: String).returns(Domains::Workflows::Entities::Outcome) }
      def result(status, reason)
        Domains::Workflows::Entities::Outcome.new(status: status, reason: reason)
      end
    end
  end
end

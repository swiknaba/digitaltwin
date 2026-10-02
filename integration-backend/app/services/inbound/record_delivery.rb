# typed: strict
# frozen_string_literal: true

module Services
  module Inbound
    # Persists a verified delivery, then classifies it and queues durable work
    # before any worker performs an effect. Recording and queueing share one
    # transaction. Workflow reads use Domains::Workflows::Workflow and the
    # queued_messages insert stays raw until Task 6.
    class RecordDelivery
      extend T::Sig

      Messaging = Domains::Messaging
      Kind = Platform::Jobs::Dto::JobKind
      Status = Dto::IngestStatus
      Outcome = T.type_alias { Kirei::Services::Result[Dto::IngestOutcome] }

      sig do
        params(agent_handle: String, worker_handle: String, master_channel_id: T.nilable(String),
               record: Messaging::RecordDelivery, outbox: Messaging::Outbox).void
      end
      def initialize(agent_handle: ENV.fetch("AGENT_HANDLE", "agent"), worker_handle: ENV.fetch("WORKER_HANDLE", "worker"),
                     master_channel_id: ENV["MASTER_CHANNEL_ID"], record: Messaging::RecordDelivery.new, outbox: Messaging::Outbox.new)
        @agent = T.let(valid_handle!(agent_handle), String)
        @worker = T.let(valid_handle!(worker_handle), String)
        @master_channel = master_channel_id
        @record = record
        @outbox = outbox
      end

      sig { params(delivery: Messaging::Dto::VerifiedDelivery).returns(Outcome) }
      def call(delivery:)
        Kirei::Services::Runner.call(self.class.name.to_s) do
          Platform::Transaction.new.call { ingest(delivery) }
        end
      end

      sig { params(delivery: Messaging::Dto::VerifiedDelivery).returns(Outcome) }
      private def ingest(delivery)
        inbox_id = Platform::Unwrap.call(@record.call(delivery: delivery)).inbox_id
        return outcome(Status::Accepted, "Duplicate delivery") unless inbox_id
        return outcome(Status::Accepted, "Revision recorded without dispatch") unless delivery.event_kind == Messaging::Dto::EventKind::Posted

        workflow = workflow_for(delivery)
        command = command_for(delivery.body)
        return outcome(Status::Rejected, "Human action requires verified member") if command && (!delivery.actor.member || delivery.actor.bot)

        if master_prompt?(delivery)
          queue(Kind::MasterPrompt, delivery, inbox_id)
        elsif command == "start"
          return outcome(Status::Rejected, "Start requires a new thread root") unless delivery.root_post && workflow.nil?

          queue(Kind::WorkflowStart, delivery, inbox_id)
        elsif workflow && dispatch_suppressed?(workflow) && command.nil?
          queue_message(workflow, inbox_id)
          notice = Messaging::Dto::OutgoingMessage.new(channel_id: delivery.channel_id, thread_id: delivery.thread_id, bot: Messaging::Dto::Bot::Worker,
                                                       role: Messaging::Dto::SpeakerRole::Writer, body: "Message queued; delivery waits for review or pause completion.",
                                                       key: "queued:#{inbox_id}")
          Platform::Unwrap.call(@outbox.enqueue(message: notice))
          outcome(Status::Accepted, "Queued under dispatch suppression")
        elsif workflow && !delivery.actor.bot && !closed?(workflow)
          queue(Kind.deserialize(command ? "workflow.#{command}" : "workflow.prompt"), delivery, inbox_id, workflow: workflow)
        else
          outcome(Status::Accepted, "No activated workflow")
        end
      end

      sig { params(handle: String).returns(String) }
      private def valid_handle!(handle)
        raise ArgumentError, "Invalid bot handle" unless handle.match?(/\A[a-z0-9_.-]+\z/)

        handle
      end

      sig { params(delivery: Messaging::Dto::VerifiedDelivery).returns(T.nilable(Domains::Workflows::Workflow)) }
      private def workflow_for(delivery)
        Domains::Workflows::Workflow.find_by(channel_id: delivery.channel_id, thread_id: delivery.thread_id, archived_at: nil)
      end

      sig { params(body: String).returns(T.nilable(String)) }
      private def command_for(body)
        command = Commands::Parser.new.call(body: body, agent_handle: @agent, worker_handle: @worker)
        command.action.serialize if command.is_a?(Commands::Dto::WorkerCommand)
      end

      # A mention anywhere in the body, not a command, so it stays out of the parser.
      sig { params(delivery: Messaging::Dto::VerifiedDelivery).returns(T::Boolean) }
      private def master_prompt?(delivery)
        (delivery.channel_id == @master_channel || delivery.body.match?(/(?:\A|\s)@#{Regexp.escape(@agent)}\b/)) &&
          delivery.actor.member && !delivery.actor.bot
      end

      sig { params(workflow: Domains::Workflows::Workflow).returns(T::Boolean) }
      private def dispatch_suppressed?(workflow)
        phase = workflow.phase
        phase == "paused" || phase.end_with?("_review")
      end

      sig { params(workflow: Domains::Workflows::Workflow).returns(T::Boolean) }
      private def closed?(workflow)
        %w[closed cancelled].include?(workflow.phase)
      end

      sig { params(workflow: Domains::Workflows::Workflow, inbox_id: Integer).void }
      private def queue_message(workflow, inbox_id)
        Domains::Workflows::Workflow.db[:queued_messages].insert(workflow_id: workflow.id, inbox_id: inbox_id, workflow_version: workflow.version)
      end

      sig do
        params(kind: Kind, delivery: Messaging::Dto::VerifiedDelivery, inbox_id: Integer,
               workflow: T.nilable(Domains::Workflows::Workflow)).returns(Outcome)
      end
      private def queue(kind, delivery, inbox_id, workflow: nil)
        payload = Domains::Commander::Dto::InboxDispatchJob.new(inbox_id: inbox_id, channel_id: delivery.channel_id, thread_id: delivery.thread_id,
                                                                workflow_id: workflow&.id, expected_version: workflow&.version)
        Platform::Jobs::Store.new.enqueue(kind: kind, payload: payload, dispatch_key: "inbox:#{inbox_id}:#{kind.serialize}")
        outcome(Status::Blocked, "Recorded durably; live Task 1 workflow dispatch is gated")
      end

      sig { params(status: Status, reason: String).returns(Outcome) }
      private def outcome(status, reason)
        Kirei::Services::Result.new(result: Dto::IngestOutcome.new(status: status, reason: reason))
      end
    end
  end
end

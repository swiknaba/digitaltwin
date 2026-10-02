# frozen_string_literal: true

module Domains
  module Mattermost
    class Router
      def initialize(db, agent_handle: ENV.fetch("AGENT_HANDLE", "agent"),
                     worker_handle: ENV.fetch("WORKER_HANDLE", "worker"),
                     master_channel_id: ENV["MASTER_CHANNEL_ID"])
        @db, @agent, @worker, @master_channel = db, agent_handle, worker_handle, master_channel_id
        raise ArgumentError, "Invalid bot handle" unless [@agent, @worker].all? { |v| v.match?(/\A[a-z0-9_.-]+\z/) }
      end

      def ingest(delivery:)
        d = delivery
        @db.transaction do
          record = { channel_id: d.channel_id, post_id: d.post_id, event_kind: d.event_kind,
                     post_revision: d.post_revision }
          id = @db[:inbox].insert_conflict(target: record.keys).insert(**record, thread_id: d.thread_id,
                                                                                 user_id: d.actor.user_id, verified_delivery: Sequel.pg_jsonb(d.serialize))
          return result("accepted", "Duplicate delivery") unless id
          return result("accepted", "Revision recorded without dispatch") unless d.event_kind == "posted"

          workflow = @db[:workflows][channel_id: d.channel_id, thread_id: d.thread_id, archived_at: nil]
          command = d.body[/\A@#{Regexp.escape(@worker)}\s+(start|approve|pause|resume|finish|cancel)\b/, 1]
          return result("rejected",
                        "Human action requires verified member") if command && (!d.actor.member || d.actor.bot)

          if (d.channel_id == @master_channel || d.body.match?(/(?:\A|\s)@#{Regexp.escape(@agent)}\b/)) && d.actor.member && !d.actor.bot
            queue("master.prompt", d, id)
          elsif command == "start"
            return result("rejected", "Start requires a new thread root") unless d.root_post && !workflow

            queue("workflow.start", d, id)
          elsif workflow && (workflow[:phase] == "paused" || workflow[:phase].end_with?("_review")) && !command
            @db[:queued_messages].insert(workflow_id: workflow[:id], inbox_id: id, workflow_version: workflow[:version])
            Outbox.new(@db).enqueue(channel_id: d.channel_id, thread_id: d.thread_id, bot: "worker", role: "writer",
                                    body: "Message queued; delivery waits for review or pause completion.", key: "queued:#{id}")
            result("accepted", "Queued under dispatch suppression")
          elsif workflow && !d.actor.bot && !%w[closed cancelled].include?(workflow[:phase])
            queue(command ? "workflow.#{command}" : "workflow.prompt", d, id, workflow: workflow)
          else
            result("accepted", "No activated workflow")
          end
        end
      end
      private def queue(kind, delivery, inbox_id, workflow: nil)
        payload = { "inbox_id" => inbox_id, "channel_id" => delivery.channel_id, "thread_id" => delivery.thread_id }
        payload.merge!("workflow_id" => workflow[:id], "expected_version" => workflow[:version]) if workflow
        Domains::Jobs::Store.new(@db).enqueue(kind: kind,
                                              payload: payload, key: "inbox:#{inbox_id}:#{kind}")
        result("blocked", "Recorded durably; live Task 1 workflow dispatch is gated")
      end
      private def result(status, reason)
        Domains::Workflows::Entities::Outcome.new(status: status, reason: reason)
      end
    end
  end
end

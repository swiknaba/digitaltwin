# typed: strict
# frozen_string_literal: true

module Domains
  module Messaging
    # Idempotent queue of chat messages. Each enqueued message gets one
    # mattermost.post job keyed by its outbox id.
    class Outbox
      extend T::Sig

      sig { params(message: Dto::OutgoingMessage).returns(Kirei::Services::Result[String]) }
      def enqueue(message:)
        if message.bot == Dto::Bot::Worker && (message.thread_id.to_s.empty? || ![Dto::SpeakerRole::Writer, Dto::SpeakerRole::Reviewer].include?(message.role))
          return failure(Dto::ErrorCode::WorkerMessageRequiresThreadAndRole, "Worker messages require thread and role")
        end

        Entities::OutboxMessage.db.transaction do
          Entities::OutboxMessage.query.insert_conflict(target: :response_key).insert(
            id: SecureRandom.uuid, response_key: message.key, channel_id: message.channel_id, thread_id: message.thread_id, bot: message.bot.serialize,
            role: message.role.serialize, body: message.body, status: Dto::OutboxStatus::Pending.serialize, created_at: Time.now.utc
          )
          persisted = T.must(Entities::OutboxMessage.find_by(response_key: message.key))
          next failure(Dto::ErrorCode::KeyReused, "Response key reused with changed content") unless same_message?(persisted, message)

          Platform::Jobs::Store.new.enqueue(kind: Platform::Jobs::Dto::JobKind::MattermostPost, payload: Dto::OutboxPostJob.new(outbox_id: persisted.id),
                                            dispatch_key: "outbox:#{persisted.id}")
          Kirei::Services::Result.new(result: persisted.id)
        end
      end

      sig { params(id: String).returns(T.nilable(Dto::OutboxItem)) }
      def item(id:)
        message = Entities::OutboxMessage.find_by(id: id)
        message && item_from(message)
      end

      sig { params(key: String).returns(T.nilable(Dto::OutboxItem)) }
      def item_by_key(key:)
        message = Entities::OutboxMessage.find_by(response_key: key)
        message && item_from(message)
      end

      # With `from`, only a row in that status changes. Returns whether a row changed.
      sig { params(id: String, remote_post_id: String, from: T.nilable(Dto::OutboxStatus)).returns(T::Boolean) }
      def mark_delivered(id:, remote_post_id:, from: nil)
        scope = Entities::OutboxMessage.query.where(id: id)
        scope = scope.where(status: from.serialize) if from
        scope.update(status: Dto::OutboxStatus::Delivered.serialize, remote_post_id: remote_post_id) == 1
      end

      sig { params(id: String).void }
      def mark_uncertain(id:)
        Entities::OutboxMessage.query.where(id: id).update(status: Dto::OutboxStatus::Uncertain.serialize)
      end

      sig { params(id: String).void }
      def mark_blocked(id:)
        Entities::OutboxMessage.query.where(id: id).update(status: Dto::OutboxStatus::Blocked.serialize)
      end

      sig { params(persisted: Entities::OutboxMessage, message: Dto::OutgoingMessage).returns(T::Boolean) }
      private def same_message?(persisted, message)
        persisted.channel_id == message.channel_id && persisted.thread_id == message.thread_id &&
          persisted.bot == message.bot && persisted.role == message.role && persisted.body == message.body
      end

      sig { params(message: Entities::OutboxMessage).returns(Dto::OutboxItem) }
      private def item_from(message)
        Dto::OutboxItem.new(id: message.id, response_key: message.response_key, channel_id: message.channel_id, thread_id: message.thread_id,
                            bot: message.bot, role: message.role, body: message.body, status: message.status, remote_post_id: message.remote_post_id,
                            created_at: message.created_at)
      end

      sig { params(code: Dto::ErrorCode, detail: String).returns(Kirei::Services::Result[String]) }
      private def failure(code, detail)
        Kirei::Services::Result.new(errors: Platform::Failure.call(code: code, detail: detail))
      end
    end
  end
end

# typed: strict
# frozen_string_literal: true

module Domains
  module Mattermost
    class Outbox
      extend T::Sig

      sig { params(channel_id: String, thread_id: T.nilable(String), bot: String, role: String, body: String, key: String).returns(String) }
      def enqueue(channel_id:, thread_id:, bot:, role:, body:, key:)
        message = OutboxMessage.new(id: SecureRandom.uuid, response_key: key, channel_id: channel_id, thread_id: thread_id, bot: bot, role: role, body: body)
        validate!(message)
        OutboxMessage.db.transaction do
          persisted = begin
            OutboxMessage.db.transaction(savepoint: true) { OutboxMessage.create(message.serialize.transform_keys(&:to_sym)) }
          rescue Sequel::UniqueConstraintViolation
            T.must(OutboxMessage.find_by(response_key: key))
          end
          raise ArgumentError, "Response key reused with changed content" unless same_message?(persisted, message)

          id = persisted.id
          Domains::Jobs::Store.new.enqueue(kind: "mattermost.post", payload: { "outbox_id" => id }, key: "outbox:#{id}")
          id
        end
      end

      private

      sig { params(message: OutboxMessage).void }
      def validate!(message)
        return unless message.bot == "worker" && (message.thread_id.to_s.empty? || !%w[writer reviewer].include?(message.role))

        raise ArgumentError, "Worker messages require thread and role"
      end

      sig { params(persisted: OutboxMessage, message: OutboxMessage).returns(T::Boolean) }
      def same_message?(persisted, message)
        persisted.channel_id == message.channel_id && persisted.thread_id == message.thread_id &&
          persisted.bot == message.bot && persisted.role == message.role && persisted.body == message.body
      end
    end
  end
end

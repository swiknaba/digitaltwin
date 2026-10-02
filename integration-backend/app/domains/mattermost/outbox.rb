# typed: strict
# frozen_string_literal: true

module Domains
  module Mattermost
    class Outbox
      extend T::Sig

      class Message < T::Struct
        const :channel_id, String
        const :thread_id, T.nilable(String)
        const :bot, String
        const :role, String
        const :body, String
      end

      Row = T.type_alias { T::Hash[Symbol, T.nilable(String)] }

      sig { params(db: Sequel::Database).void }
      def initialize(db)
        @db = T.let(db, Sequel::Database)
      end

      sig { params(channel_id: String, thread_id: T.nilable(String), bot: String, role: String, body: String, key: String).returns(String) }
      def enqueue(channel_id:, thread_id:, bot:, role:, body:, key:)
        message = Message.new(channel_id: channel_id, thread_id: thread_id, bot: bot, role: role, body: body)
        validate!(message)
        @db.transaction do
          @db[:outbox].insert_conflict(target: :response_key).insert(
            channel_id: message.channel_id,
            thread_id: message.thread_id,
            bot: message.bot,
            role: message.role,
            body: message.body,
            id: SecureRandom.uuid,
            response_key: key
          )
          row = row_from(@db[:outbox][response_key: key])
          raise ArgumentError, "Response key reused with changed content" unless same_message?(row, message)

          id = row_string(row, :id)
          Domains::Jobs::Store.new(@db).enqueue(kind: "mattermost.post", payload: { "outbox_id" => id }, key: "outbox:#{id}")
          id
        end
      end

      private

      sig { params(message: Message).void }
      def validate!(message)
        return unless message.bot == "worker" && (message.thread_id.to_s.empty? || !%w[writer reviewer].include?(message.role))

        raise ArgumentError, "Worker messages require thread and role"
      end

      sig { params(value: Object).returns(Row) }
      def row_from(value)
        raise ArgumentError, "Missing outbox item" unless value.is_a?(Hash)

        row = T.let({}, Row)
        value.each do |key, item|
          raise ArgumentError, "Malformed outbox item" unless key.is_a?(Symbol) && (item.is_a?(String) || item.nil?)

          row[key] = item
        end
        row
      end

      sig { params(row: Row, message: Message).returns(T::Boolean) }
      def same_message?(row, message)
        row_string(row, :channel_id) == message.channel_id && optional_row_string(row, :thread_id) == message.thread_id &&
          row_string(row, :bot) == message.bot && row_string(row, :role) == message.role && row_string(row, :body) == message.body
      end

      sig { params(row: Row, key: Symbol).returns(String) }
      def row_string(row, key)
        value = row.fetch(key)
        raise ArgumentError, "Malformed outbox item" unless value.is_a?(String)

        value
      end

      sig { params(row: Row, key: Symbol).returns(T.nilable(String)) }
      def optional_row_string(row, key)
        value = row[key]
        value
      end
    end
  end
end

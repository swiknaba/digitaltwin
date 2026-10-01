# frozen_string_literal: true

module Domains
  module Mattermost
    class Outbox
      def initialize(db) = @db = db

      def enqueue(channel_id:, thread_id:, bot:, role:, body:, key:)
        raise ArgumentError,
              "Worker messages require thread and role" if bot == "worker" && (thread_id.to_s.empty? || !%w[
                writer reviewer
              ].include?(role))

        content = { channel_id: channel_id, thread_id: thread_id, bot: bot, role: role, body: body }
        @db.transaction do
          @db[:outbox].insert_conflict(target: :response_key).insert(**content, id: SecureRandom.uuid,
                                                                                response_key: key)
          row = @db[:outbox][response_key: key]
          raise ArgumentError, "Response key reused with changed content" unless content.all? { |k, v| row[k] == v }

          Domains::Jobs::Store.new(@db).enqueue(kind: "mattermost.post", payload: { "outbox_id" => row[:id] },
                                                key: "outbox:#{row[:id]}")
          row[:id]
        end
      end
    end
  end
end

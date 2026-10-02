# typed: strict
# frozen_string_literal: true

module Domains
  module Messaging
    # Read access to persisted verified deliveries.
    class Inbox
      extend T::Sig

      sig { params(id: Integer).returns(T.nilable(Dto::InboxRecord)) }
      def find(id:)
        entry = Entities::InboxEntry.find_by(id: id)
        entry && record(entry)
      end

      # Newest first.
      sig { params(since: Time, limit: Integer).returns(T::Array[Dto::InboxRecord]) }
      def recent(since:, limit:)
        query = Entities::InboxEntry.query.where(Sequel.expr(:created_at) > since).order(Sequel.desc(:id)).limit(limit)
        Entities::InboxEntry.resolve(query).map { |entry| record(entry) }
      end

      # Takes a row lock inside the caller's transaction, which serializes
      # work bound to one inbox record.
      sig { params(id: Integer).void }
      def lock(id:)
        Entities::InboxEntry.query.where(id: id).select(:id).for_update.all
      end

      sig { params(entry: Entities::InboxEntry).returns(Dto::InboxRecord) }
      private def record(entry)
        Dto::InboxRecord.new(id: entry.id, channel_id: entry.channel_id, thread_id: entry.thread_id, post_id: entry.post_id, user_id: entry.user_id,
                             event_kind: entry.event_kind, post_revision: entry.post_revision, verified_delivery: entry.verified_delivery,
                             created_at: entry.created_at)
      end
    end
  end
end

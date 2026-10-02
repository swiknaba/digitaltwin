# typed: strict
# frozen_string_literal: true

module Domains
  module Messaging
    # Read access to persisted verified deliveries.
    class Inbox
      extend T::Sig

      sig { params(id: String).returns(T.nilable(Dto::InboxRecord)) }
      def find(id:)
        entry = Entities::InboxEntry.find_by(id: id)
        entry && record(entry)
      end

      # Newest first. A malformed row counts toward the limit but is skipped,
      # so one corrupt row does not hide the other recent context.
      sig { params(since: Time, limit: Integer).returns(T::Array[Dto::InboxRecord]) }
      def recent(since:, limit:)
        query = Entities::InboxEntry.query.where(Sequel.expr(:created_at) > since).order(Sequel.desc(:created_at), Sequel.desc(:id)).limit(limit)
        query.select_map(:id).grep(String).filter_map do |id|
          record(strictly { T.must(Entities::InboxEntry.resolve_first(Entities::InboxEntry.query.where(id: id))) })
        rescue Errors::MalformedRecord
          nil
        end
      end

      # Takes a row lock inside the caller's transaction, which serializes
      # work bound to one inbox record.
      sig { params(id: String).void }
      def lock(id:)
        Entities::InboxEntry.query.where(id: id).select(:id).for_update.all
      end

      # from_hash raises RuntimeError for missing or unknown props and KeyError
      # for unknown enum values; constructors raise TypeError for wrong types.
      sig { params(blk: T.proc.returns(Entities::InboxEntry)).returns(Entities::InboxEntry) }
      private def strictly(&blk)
        yield
      rescue RuntimeError, KeyError, TypeError
        raise Errors::MalformedRecord, "Malformed durable inbox record"
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

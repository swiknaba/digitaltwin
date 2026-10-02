# typed: strict
# frozen_string_literal: true

module Platform
  module Audit
    # Append-only audit receipts keyed by a unique event key. `details` is a
    # T::Struct whose serialized form is stored as JSONB.
    class Log
      extend T::Sig

      # Raises Sequel::UniqueConstraintViolation when the event key exists.
      sig do
        params(event_key: String, action: String, details: T::Struct, user_id: T.nilable(String),
               channel_id: T.nilable(String), post_id: T.nilable(String)).void
      end
      def record(event_key:, action:, details:, user_id: nil, channel_id: nil, post_id: nil)
        Entities::Entry.query.insert(event_key: event_key, action: action, details: Sequel.pg_jsonb(details.serialize), user_id: user_id, channel_id: channel_id, post_id: post_id)
      end

      # Inserts unless the event key exists; returns whether it inserted.
      sig do
        params(event_key: String, action: String, details: T::Struct, user_id: T.nilable(String),
               channel_id: T.nilable(String), post_id: T.nilable(String)).returns(T::Boolean)
      end
      def record_once(event_key:, action:, details:, user_id: nil, channel_id: nil, post_id: nil)
        inserted = Entities::Entry.query.insert_conflict(target: :event_key)
                                  .insert(event_key: event_key, action: action, details: Sequel.pg_jsonb(details.serialize), user_id: user_id, channel_id: channel_id, post_id: post_id)
        !inserted.nil?
      end

      sig { params(event_key: String).returns(T.nilable(Dto::Receipt)) }
      def find(event_key:)
        entry = Entities::Entry.find_by(event_key: event_key)
        entry && Dto::Receipt.new(action: entry.action, details: entry.details)
      end
    end
  end
end

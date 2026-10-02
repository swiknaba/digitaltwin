# typed: strict
# frozen_string_literal: true

module Domains
  module Commander
    # Revalidates a persisted inbox record against Mattermost before it becomes
    # authority for a controller action.
    class Source
      extend T::Sig

      InboxRow = T.type_alias { T::Hash[Symbol, Object] }
      InboxId = T.type_alias { T.any(Integer, String) }
      VerifiedDeliveryRecord = T.type_alias { T::Hash[String, Object] }

      module DeliveryResolver
        extend T::Helpers
        extend T::Sig

        interface!

        sig { abstract.params(post_id: String, channel_id: String, event_kind: String).returns(Domains::Mattermost::VerifiedDelivery) }
        def delivery(post_id:, channel_id:, event_kind:); end
      end

      sig do
        params(
          db: Sequel::Database,
          resolver: DeliveryResolver,
          membership: T.proc.params(channel_id: String, user_id: String).returns(T::Boolean)
        ).void
      end
      def initialize(db, resolver:, membership:)
        @db = db
        @resolver = resolver
        @membership = membership
      end

      sig { params(id: InboxId, destination: T.nilable(String)).returns(Domains::Mattermost::VerifiedDelivery) }
      def human(id, destination: nil)
        row = inbox_row(id)
        delivery = @resolver.delivery(post_id: string_value(row, :post_id), channel_id: string_value(row, :channel_id), event_kind: "posted")
        raise ArgumentError, "Human source changed" unless verified_human?(delivery, row)
        raise ArgumentError, "Destination membership required" if destination && !@membership.call(destination, delivery.actor.user_id)

        delivery
      end

      private

      sig { params(id: InboxId).returns(InboxRow) }
      def inbox_row(id)
        row = @db[:inbox][id: id]
        raise ArgumentError, "Missing verified source" unless row.is_a?(Hash)

        row
      end

      sig { params(row: InboxRow, key: Symbol).returns(String) }
      def string_value(row, key)
        value = row.fetch(key)
        raise ArgumentError, "Invalid verified source" unless value.is_a?(String)

        value
      end

      sig { params(row: InboxRow).returns(String) }
      def verified_delivery(row)
        value = row.fetch(:verified_delivery)
        json = Hash.try_convert(value)
        raise ArgumentError, "Invalid verified source" unless json

        record = T.let({}, VerifiedDeliveryRecord)
        json.each do |key, item|
          raise ArgumentError, "Invalid verified source" unless key.is_a?(String)

          record[key] = item
        end
        body = record.fetch("body") { raise ArgumentError, "Invalid verified source" }
        raise ArgumentError, "Invalid verified source" unless body.is_a?(String)

        body
      end

      sig { params(delivery: Domains::Mattermost::VerifiedDelivery, row: InboxRow).returns(T::Boolean) }
      def verified_human?(delivery, row)
        delivery.actor.member && !delivery.actor.bot &&
          delivery.actor.user_id == string_value(row, :user_id) &&
          delivery.post_revision == integer_value(row, :post_revision) &&
          delivery.body == verified_delivery(row)
      end

      sig { params(row: InboxRow, key: Symbol).returns(Integer) }
      def integer_value(row, key)
        value = row.fetch(key)
        raise ArgumentError, "Invalid verified source" unless value.is_a?(Integer)

        value
      end
    end
  end
end

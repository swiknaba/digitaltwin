# typed: strict
# frozen_string_literal: true

module Domains
  module Messaging
    # Persists a verified delivery once per channel, post, event kind, and
    # revision. A replay records nothing and reports a duplicate.
    class RecordDelivery
      extend T::Sig

      sig { params(delivery: Dto::VerifiedDelivery).returns(Kirei::Services::Result[Dto::RecordedDelivery]) }
      def call(delivery:)
        Kirei::Services::Runner.call(self.class.name.to_s) do
          id = Entities::InboxEntry.query.insert_conflict(target: %i[channel_id post_id event_kind post_revision]).insert(
            id: Entities::InboxEntry.generate_human_id, channel_id: delivery.channel_id, post_id: delivery.post_id, event_kind: delivery.event_kind.serialize,
            post_revision: delivery.post_revision, thread_id: delivery.thread_id, user_id: delivery.actor.user_id,
            verified_delivery: Sequel.pg_jsonb(delivery.serialize)
          )
          recorded = id.is_a?(String) ? Dto::RecordedDelivery.new(inbox_id: id, duplicate: false) : Dto::RecordedDelivery.new(inbox_id: nil, duplicate: true)
          Kirei::Services::Result.new(result: recorded)
        end
      end
    end
  end
end

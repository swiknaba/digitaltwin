# typed: strict
# frozen_string_literal: true

module Domains
  module Messaging
    # Revalidates a persisted inbox record against chat REST before it becomes
    # authority for a controller action. Verifier exceptions propagate.
    class VerifyHumanSource
      extend T::Sig

      sig { params(verifier: DeliveryVerifier, membership: MembershipCheck, inbox: Inbox).void }
      def initialize(verifier:, membership:, inbox: Inbox.new)
        @verifier = verifier
        @membership = membership
        @inbox = inbox
      end

      sig { params(inbox_id: Integer, destination: T.nilable(String)).returns(Kirei::Services::Result[Dto::VerifiedDelivery]) }
      def call(inbox_id:, destination: nil)
        Kirei::Services::Runner.call(self.class.name.to_s) do
          record = @inbox.find(id: inbox_id)
          next failure(Dto::ErrorCode::MissingSource, "Missing verified source") unless record

          delivery = @verifier.delivery(post_id: record.post_id, channel_id: record.channel_id, event_kind: Dto::EventKind::Posted)
          next failure(Dto::ErrorCode::SourceChanged, "Human source changed") unless verified_human?(delivery, record)
          if destination && !@membership.member?(channel_id: destination, user_id: delivery.actor.user_id)
            next failure(Dto::ErrorCode::DestinationMembershipRequired, "Destination membership required")
          end

          Kirei::Services::Result.new(result: delivery)
        end
      end

      sig { params(delivery: Dto::VerifiedDelivery, record: Dto::InboxRecord).returns(T::Boolean) }
      private def verified_human?(delivery, record)
        delivery.actor.member && !delivery.actor.bot && delivery.actor.user_id == record.user_id &&
          delivery.post_revision == record.post_revision && delivery.body == record.verified_delivery.body
      end

      sig { params(code: Dto::ErrorCode, detail: String).returns(Kirei::Services::Result[Dto::VerifiedDelivery]) }
      private def failure(code, detail)
        Kirei::Services::Result.new(errors: Platform::Failure.call(code: code, detail: detail))
      end
    end
  end
end

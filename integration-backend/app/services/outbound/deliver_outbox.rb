# typed: strict
# frozen_string_literal: true

module Services
  module Outbound
    # Delivers one outbox message as the configured bot after verifying
    # identity, membership, and thread root. An unknown post result stays
    # uncertain and is never retried; ReconcileOutbox settles it only from
    # server evidence.
    class DeliverOutbox
      extend T::Sig
      include Platform::Jobs::Handler

      Api = Adapters::Mattermost::Api
      Bot = Domains::Messaging::Dto::Bot
      Status = Domains::Messaging::Dto::OutboxStatus

      sig { params(apis: T::Hash[Bot, Api], bot_ids: T::Hash[Bot, String], outbox: Domains::Messaging::Outbox).void }
      def initialize(apis:, bot_ids:, outbox: Domains::Messaging::Outbox.new)
        @apis = apis
        @bot_ids = bot_ids
        @outbox = outbox
      end

      sig { override.params(job: Platform::Jobs::Dto::ClaimedJob).returns(Platform::Jobs::Dto::Decision) }
      def call(job:)
        Kirei::Services::Runner.call(self.class.name.to_s) do
          payload = Domains::Messaging::Dto::OutboxPostJob.from_hash(job.payload, true)
          item = @outbox.item(id: payload.outbox_id)
          raise ArgumentError, "Unknown outbox item" unless item
          next Platform::Jobs::Dto::Decision.complete if item.status == Status::Delivered

          raise "Outbox requires reconciliation" unless item.status == Status::Pending

          api = @apis.fetch(item.bot)
          bot = @bot_ids.fetch(item.bot)
          VerifyDestination.new.call(api: api, item: item, bot: bot)
          Platform::Transaction.new.call do
            raise "Lost external effect lease" unless job.lease.begin_effect

            @outbox.mark_uncertain(id: item.id)
          end
          remote = api.create_post(Adapters::Mattermost::Dto::NewPost.new(channel_id: item.channel_id, root_id: item.thread_id || "", message: item.body,
                                                                          props: { "digitaltwin_response_key" => item.response_key }))
          VerifyPostedResult.new.call(post: remote, item: item, bot: bot)
          @outbox.mark_delivered(id: item.id, remote_post_id: remote.id)
          Platform::Jobs::Dto::Decision.complete
        end
      end
    end
  end
end

# typed: strict
# frozen_string_literal: true

module Services
  module Outbound
    # Settles an uncertain outbox delivery from server evidence: exactly one
    # verified post with the message's response key. It never posts. The
    # result is Delivered, or Uncertain when no single match exists.
    class ReconcileOutbox
      extend T::Sig

      Api = Adapters::Mattermost::Api
      Bot = Domains::Messaging::Dto::Bot
      Status = Domains::Messaging::Dto::OutboxStatus
      Outcome = T.type_alias { Kirei::Services::Result[Status] }

      sig { params(apis: T::Hash[Bot, Api], bot_ids: T::Hash[Bot, String], outbox: Domains::Messaging::Outbox).void }
      def initialize(apis:, bot_ids:, outbox: Domains::Messaging::Outbox.new)
        @apis = apis
        @bot_ids = bot_ids
        @outbox = outbox
      end

      sig { params(outbox_id: String).returns(Outcome) }
      def call(outbox_id:)
        Kirei::Services::Runner.call(self.class.name.to_s) do
          item = @outbox.item(id: outbox_id)
          next failure(Dto::ErrorCode::NotUncertain, "Expected uncertain delivery") unless item && item.status == Status::Uncertain

          api = @apis.fetch(item.bot)
          bot = @bot_ids.fetch(item.bot)
          VerifyDestination.new.call(api: api, item: item, bot: bot)
          since = [(item.created_at.to_f * 1000).to_i - 1000, 1].max
          history = api.channel_history(channel_id: item.channel_id, since: since, page: nil)
          next failure(Dto::ErrorCode::MalformedHistory, "Malformed Mattermost post list") unless history.entries.all?(&:post)

          matches = history.entries.filter_map(&:post).select { |post| post.props["digitaltwin_response_key"] == item.response_key }
          next Kirei::Services::Result.new(result: Status::Uncertain) unless matches.size == 1

          post = matches.fetch(0)
          VerifyPostedResult.new.call(post: post, item: item, bot: bot)
          settle(item, post)
          Kirei::Services::Result.new(result: Status::Delivered)
        end
      end

      sig { params(item: Domains::Messaging::Dto::OutboxItem, post: Adapters::Mattermost::Dto::Post).void }
      private def settle(item, post)
        Platform::Transaction.new.call do
          @outbox.mark_delivered(id: item.id, remote_post_id: post.id, from: Status::Uncertain)
          jobs = Platform::Jobs::Store.new
          job = jobs.find_by_key(dispatch_key: "outbox:#{item.id}")
          jobs.close_uncertain(id: job.id) if job
        end
      end

      sig { params(code: Dto::ErrorCode, detail: String).returns(Outcome) }
      private def failure(code, detail)
        Kirei::Services::Result.new(errors: Platform::Failure.call(code: code, detail: detail))
      end
    end
  end
end

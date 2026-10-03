# typed: strict
# frozen_string_literal: true

module Services
  module Workflows
    # Checks that the worker credential is the configured bot and a member of
    # the project channel before it creates or proves a start thread.
    class VerifyThreadBot
      extend T::Sig

      sig { params(api: Adapters::Mattermost::Api, bot_id: String).void }
      def initialize(api:, bot_id:)
        @api = api
        @bot = bot_id
      end

      sig { params(channel_id: String).returns(T::Boolean) }
      def call(channel_id:)
        me = @api.me
        member = @api.member(channel_id: channel_id, user_id: @bot)
        me.id == @bot && me.bot && !member.nil? && member.channel_id == channel_id && member.user_id == @bot
      end
    end
  end
end

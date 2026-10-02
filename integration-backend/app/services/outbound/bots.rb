# typed: strict
# frozen_string_literal: true

module Services
  module Outbound
    # Builds the per-bot Mattermost APIs and bot user IDs from ENV.
    class Bots
      extend T::Sig

      Bot = Domains::Messaging::Dto::Bot

      sig { returns(T::Hash[Bot, Adapters::Mattermost::Api]) }
      def self.apis_from_env
        url = ENV.fetch("MATTERMOST_URL")
        Bot.values.to_h do |bot|
          client = Adapters::Mattermost::Client.new(url: url, token_file: ENV.fetch("MATTERMOST_#{bot.serialize.upcase}_TOKEN_FILE"))
          [bot, Adapters::Mattermost::Api.new(client: client)]
        end
      end

      sig { returns(T::Hash[Bot, String]) }
      def self.ids_from_env
        Bot.values.to_h { |bot| [bot, ENV.fetch("MATTERMOST_#{bot.serialize.upcase}_BOT_ID")] }
      end
    end
  end
end

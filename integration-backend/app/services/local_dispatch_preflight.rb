# typed: strict
# frozen_string_literal: true

module Services
  # Performs the read-only checks that an explicitly activated local worker or
  # listener must pass immediately before it can own runtime effects.
  class LocalDispatchPreflight
    extend T::Sig

    Bot = Domains::Messaging::Dto::Bot
    Mattermost = Adapters::Mattermost
    DEFAULT_API_FACTORY = T.let(->(url, token_file) { Mattermost::Api.new(client: Mattermost::Client.new(url: url, token_file: token_file)) },
                                T.proc.params(url: String, token_file: String).returns(Mattermost::Api))
    DEFAULT_PANES = T.let(-> { Adapters::Herdr::Client.new.panes }, T.proc.returns(T::Array[Adapters::Herdr::Dto::PaneSummary]))

    sig do
      params(configuration: Configuration,
             api_factory: T.proc.params(url: String, token_file: String).returns(Mattermost::Api),
             panes: T.proc.returns(T::Array[Adapters::Herdr::Dto::PaneSummary])).void
    end
    def initialize(configuration:, api_factory: DEFAULT_API_FACTORY, panes: DEFAULT_PANES)
      @configuration = configuration
      @api_factory = api_factory
      @panes = panes
    end

    sig { void }
    def call
      return unless @configuration.local_dispatch_enabled?

      url = required(@configuration.mattermost_url, "MATTERMOST_URL")
      listener = @api_factory.call(url, required(@configuration.mattermost_listener_token_file, "MATTERMOST_LISTENER_TOKEN_FILE"))
      listener.me
      bot_ids = verified_bots(url)
      required(@configuration.mattermost_channel_ids, "MATTERMOST_CHANNEL_IDS").each do |channel_id|
        raise "Configured channel identity mismatch" unless listener.channel(channel_id).id == channel_id

        bot_ids.each_value { |bot_id| listener.member!(channel_id: channel_id, user_id: bot_id) }
      end
      @panes.call
    end

    sig { params(url: String).returns(T::Hash[Bot, String]) }
    private def verified_bots(url)
      Bot.values.to_h do |bot|
        key = bot.serialize.upcase
        token_file = required(@configuration.mattermost_bot_token_files[bot], "MATTERMOST_#{key}_TOKEN_FILE")
        expected_id = required(@configuration.mattermost_bot_ids[bot], "MATTERMOST_#{key}_BOT_ID")
        actual = @api_factory.call(url, token_file).me
        raise "Configured bot identity mismatch" unless actual.id == expected_id && actual.bot

        [bot, actual.id]
      end
    end

    sig { type_parameters(:Value).params(value: T.nilable(T.type_parameter(:Value)), name: String).returns(T.type_parameter(:Value)) }
    private def required(value, name)
      value || raise(ArgumentError, "#{name} is required")
    end
  end
end

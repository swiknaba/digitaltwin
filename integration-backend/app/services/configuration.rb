# typed: strict
# frozen_string_literal: true

module Services
  # Typed snapshot of the process environment. It is the only reader of ENV
  # under app/. A variable without a default stays nil here, so a process
  # fails only when Composition builds an object that needs it.
  class Configuration < T::Struct
    extend T::Sig

    Bot = Domains::Messaging::Dto::Bot

    DEFAULT_CALLBACK_URL = "http://backend-web:3000"
    COMMANDER_HANDLE = "commander"
    AGENT_HANDLE = "agent"
    DEFAULT_WORKSPACE_ROOT = "/workspace/repos"
    DEFAULT_WORKTREE_ROOT = "/workspace/worktrees"
    DEFAULT_COMMANDER_WORKSPACE = "/workspace/commander"
    DEFAULT_HEARTBEAT_DIR = "/tmp"

    const :mattermost_url, T.nilable(String), default: nil
    const :mattermost_listener_token_file, T.nilable(String), default: nil
    # MATTERMOST_COMMANDER_* and MATTERMOST_AGENT_* identify the delivery bots.
    const :mattermost_bot_token_files, T::Hash[Bot, String], default: {}
    const :mattermost_bot_ids, T::Hash[Bot, String], default: {}
    const :mattermost_local_bot_ids, T.nilable(T::Array[String]), default: nil
    const :mattermost_peer_bot_ids, T::Array[String], default: []
    const :mattermost_channel_ids, T.nilable(T::Array[String]), default: nil
    const :commander_channel_id, T.nilable(String), default: nil
    # Parsed once; a malformed file fails startup. A commander-only file is
    # valid; starts then fail with RolesMissing.
    const :roles, T.nilable(Domains::Workflows::Dto::RoleFile), default: nil
    const :callback_url, String, default: DEFAULT_CALLBACK_URL
    const :commander_handle, String, default: COMMANDER_HANDLE
    const :agent_handle, String, default: AGENT_HANDLE
    const :workspace_root, String, default: DEFAULT_WORKSPACE_ROOT
    const :worktree_root, String, default: DEFAULT_WORKTREE_ROOT
    const :commander_workspace, String, default: DEFAULT_COMMANDER_WORKSPACE
    const :heartbeat_dir, String, default: DEFAULT_HEARTBEAT_DIR
    const :chat_validation_mode, T::Boolean, default: false
    # Nil keeps every runtime effect gated. This value can only come from the
    # strict, local-only acknowledgement file; there is no boolean ENV switch.
    const :local_dispatch_activation, T.nilable(Domains::Workflows::Dto::LocalDispatchActivation), default: nil

    sig { returns(Configuration) }
    def self.from_env
      roles = roles_from_env
      activation = local_dispatch_activation_from_env
      validate_local_dispatch!(activation: activation, roles: roles, role_config_path: ENV["ROLE_CONFIG_FILE"])
      commander_handle = ENV.fetch("COMMANDER_HANDLE", COMMANDER_HANDLE)
      agent_handle = ENV.fetch("AGENT_HANDLE", AGENT_HANDLE)
      raise ArgumentError, "Commander and project agent handles must differ" if commander_handle == agent_handle

      bot_ids = per_bot("BOT_ID")
      local_bot_ids = bot_ids.size == Bot.values.size ? bot_ids.values : nil

      new(
        mattermost_url: ENV["MATTERMOST_URL"], mattermost_listener_token_file: ENV["MATTERMOST_LISTENER_TOKEN_FILE"],
        mattermost_bot_token_files: per_bot("TOKEN_FILE"), mattermost_bot_ids: bot_ids,
        mattermost_local_bot_ids: local_bot_ids, mattermost_peer_bot_ids: ENV.fetch("MATTERMOST_PEER_BOT_IDS", "").split(","),
        mattermost_channel_ids: ENV["MATTERMOST_CHANNEL_IDS"]&.split(","), commander_channel_id: ENV["COMMANDER_CHANNEL_ID"], roles: roles,
        callback_url: ENV.fetch("DIGITALTWIN_CALLBACK_URL", DEFAULT_CALLBACK_URL), commander_handle: commander_handle,
        agent_handle: agent_handle, workspace_root: ENV.fetch("WORKSPACE_ROOT", DEFAULT_WORKSPACE_ROOT),
        worktree_root: ENV.fetch("WORKTREE_ROOT", DEFAULT_WORKTREE_ROOT), commander_workspace: ENV.fetch("COMMANDER_WORKSPACE", DEFAULT_COMMANDER_WORKSPACE),
        heartbeat_dir: ENV.fetch("HEARTBEAT_DIR", DEFAULT_HEARTBEAT_DIR),
        chat_validation_mode: ENV["CHAT_VALIDATION_MODE"] == "1", local_dispatch_activation: activation
      )
    end

    sig { returns(T::Boolean) }
    def local_dispatch_enabled? = !local_dispatch_activation.nil?

    sig { returns(T::Boolean) }
    def chat_transport_enabled? = chat_validation_mode || local_dispatch_enabled?

    sig { params(suffix: String).returns(T::Hash[Bot, String]) }
    private_class_method def self.per_bot(suffix)
      Bot.values.each_with_object(T.let({}, T::Hash[Bot, String])) do |bot, values|
        value = ENV["MATTERMOST_#{bot.serialize.upcase}_#{suffix}"]
        values[bot] = value if value
      end
    end

    sig { returns(T.nilable(Domains::Workflows::Dto::RoleFile)) }
    private_class_method def self.roles_from_env
      path = ENV["ROLE_CONFIG_FILE"]
      path ? Domains::Workflows::Records.role_file_from_json(File.read(path)) : nil
    end

    sig { returns(T.nilable(Domains::Workflows::Dto::LocalDispatchActivation)) }
    private_class_method def self.local_dispatch_activation_from_env
      path = ENV["LOCAL_DISPATCH_ACTIVATION_FILE"]
      return nil unless path

      mode = File.stat(path).mode & 0o777
      raise ArgumentError, "Local dispatch activation file is group/world writable" unless (mode & 0o022).zero?

      activation = Domains::Workflows::Dto::LocalDispatchActivation.from_hash(JSON.parse(File.read(path)), true)
      valid = activation.schema == Domains::Workflows::Dto::LocalDispatchActivation::SCHEMA && activation.scope == "local"
      valid &&= /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/.match?(activation.confirmed_at)
      valid &&= /\A[0-9a-f]{64}\z/.match?(activation.role_config_sha256)
      raise ArgumentError, "Invalid local dispatch activation" unless valid

      activation
    rescue Errno::ENOENT, JSON::ParserError, RuntimeError, KeyError, TypeError, ArgumentError => error
      raise ArgumentError, "Invalid local dispatch activation (#{error.class})"
    end

    sig do
      params(activation: T.nilable(Domains::Workflows::Dto::LocalDispatchActivation), roles: T.nilable(Domains::Workflows::Dto::RoleFile),
             role_config_path: T.nilable(String)).void
    end
    private_class_method def self.validate_local_dispatch!(activation:, roles:, role_config_path:)
      return unless activation

      raise ArgumentError, "Local dispatch role configuration path is missing" unless role_config_path
      raise ArgumentError, "Local dispatch role configuration changed after activation" unless Digest::SHA256.file(role_config_path).hexdigest == activation.role_config_sha256

      assignments = roles&.assignments
      raise ArgumentError, "Local dispatch requires Writer and Reviewer roles" unless assignments

      complete = [assignments.writer, assignments.reviewer].all? { |role| Domains::Sessions::ConfigurationPolicy.complete?(role) }
      raise ArgumentError, "Local dispatch role configuration is incomplete" unless complete

      raise ArgumentError, "Local dispatch roles must differ by provider and family" unless Domains::Workflows::Policy.new.diverse?(assignments.writer, assignments.reviewer)

      commander = roles.commander
      raise ArgumentError, "Local dispatch Commander must use Hermes" if commander && commander.cli != "hermes"
      raise ArgumentError, "Local dispatch Commander configuration is incomplete" if commander && !Domains::Sessions::ConfigurationPolicy.complete?(commander)

      required = [ENV["MATTERMOST_URL"], ENV["MATTERMOST_LISTENER_TOKEN_FILE"], ENV["MATTERMOST_CHANNEL_IDS"]]
      raise ArgumentError, "Local dispatch chat configuration is incomplete" if required.any? { |value| value.nil? || value.empty? }

      Domains::Messaging::Dto::Bot.values.each do |bot|
        key = bot.serialize.upcase
        token_file = ENV["MATTERMOST_#{key}_TOKEN_FILE"]
        bot_id = ENV["MATTERMOST_#{key}_BOT_ID"]
        raise ArgumentError, "Local dispatch #{key} bot configuration is incomplete" unless token_file && !token_file.empty? && bot_id && !bot_id.empty?
        raise ArgumentError, "Local dispatch #{key} credential file is unreadable" unless File.file?(token_file) && File.readable?(token_file) && !File.read(token_file).strip.empty?
      end

      channels = ENV.fetch("MATTERMOST_CHANNEL_IDS").split(",")
      commander_channel = ENV["COMMANDER_CHANNEL_ID"]
      if commander && (commander_channel.nil? || commander_channel.empty?)
        raise ArgumentError, "Local dispatch Commander requires a monitored channel"
      end
      if commander_channel && !commander_channel.empty? && !channels.include?(commander_channel)
        raise ArgumentError, "Local dispatch Commander channel is not monitored"
      end
    end
  end
end

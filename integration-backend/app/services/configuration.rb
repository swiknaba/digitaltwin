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
    DEFAULT_AGENT_HANDLE = "agent"
    DEFAULT_WORKER_HANDLE = "worker"
    DEFAULT_WORKSPACE_ROOT = "/workspace/repos"
    DEFAULT_WORKTREE_ROOT = "/workspace/worktrees"
    DEFAULT_HEARTBEAT_DIR = "/tmp"

    const :mattermost_url, T.nilable(String), default: nil
    const :mattermost_listener_token_file, T.nilable(String), default: nil
    # MATTERMOST_<BOT>_TOKEN_FILE and MATTERMOST_<BOT>_BOT_ID for each set bot.
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
    const :agent_handle, String, default: DEFAULT_AGENT_HANDLE
    const :worker_handle, String, default: DEFAULT_WORKER_HANDLE
    const :workspace_root, String, default: DEFAULT_WORKSPACE_ROOT
    const :worktree_root, String, default: DEFAULT_WORKTREE_ROOT
    const :heartbeat_dir, String, default: DEFAULT_HEARTBEAT_DIR
    const :chat_validation_mode, T::Boolean, default: false

    sig { returns(Configuration) }
    def self.from_env
      new(
        mattermost_url: ENV["MATTERMOST_URL"], mattermost_listener_token_file: ENV["MATTERMOST_LISTENER_TOKEN_FILE"],
        mattermost_bot_token_files: per_bot("TOKEN_FILE"), mattermost_bot_ids: per_bot("BOT_ID"),
        mattermost_local_bot_ids: ENV["MATTERMOST_LOCAL_BOT_IDS"]&.split(","), mattermost_peer_bot_ids: ENV.fetch("MATTERMOST_PEER_BOT_IDS", "").split(","),
        mattermost_channel_ids: ENV["MATTERMOST_CHANNEL_IDS"]&.split(","), commander_channel_id: ENV["COMMANDER_CHANNEL_ID"], roles: roles_from_env,
        callback_url: ENV.fetch("DIGITALTWIN_CALLBACK_URL", DEFAULT_CALLBACK_URL), agent_handle: ENV.fetch("AGENT_HANDLE", DEFAULT_AGENT_HANDLE),
        worker_handle: ENV.fetch("WORKER_HANDLE", DEFAULT_WORKER_HANDLE), workspace_root: ENV.fetch("WORKSPACE_ROOT", DEFAULT_WORKSPACE_ROOT),
        worktree_root: ENV.fetch("WORKTREE_ROOT", DEFAULT_WORKTREE_ROOT), heartbeat_dir: ENV.fetch("HEARTBEAT_DIR", DEFAULT_HEARTBEAT_DIR),
        chat_validation_mode: ENV["CHAT_VALIDATION_MODE"] == "1"
      )
    end

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
  end
end

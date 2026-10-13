# typed: strict
# frozen_string_literal: true

module Services
  # Kirei owns only future commitments. Commander runtime credentials and the
  # production delivery transport are operator-managed and deliberately absent.
  class Configuration < T::Struct
    extend T::Sig

    DEFAULT_HEARTBEAT_DIR = "/tmp"

    const :heartbeat_dir, String, default: DEFAULT_HEARTBEAT_DIR
    const :commander_bridge_url, T.nilable(String), default: nil
    const :commander_bridge_identity_file, T.nilable(String), default: nil
    const :capability_secret_file, T.nilable(String), default: nil

    sig { returns(Configuration) }
    def self.from_env
      new(
        heartbeat_dir: ENV.fetch("HEARTBEAT_DIR", DEFAULT_HEARTBEAT_DIR),
        commander_bridge_url: ENV["COMMANDER_BRIDGE_URL"],
        commander_bridge_identity_file: ENV["COMMANDER_BRIDGE_IDENTITY_FILE"],
        capability_secret_file: ENV["FUTURE_TASK_CAPABILITY_SECRET_FILE"]
      )
    end
  end
end

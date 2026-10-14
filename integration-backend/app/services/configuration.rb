# typed: strict
# frozen_string_literal: true

module Services
  # Kirei owns only future commitments. Commander runtime credentials and the
  # production delivery transport are operator-managed and deliberately absent.
  class Configuration < T::Struct
    extend T::Sig

    DEFAULT_HEARTBEAT_DIR = "/tmp"

    const :heartbeat_dir, String, default: DEFAULT_HEARTBEAT_DIR
    const :opencode_url, T.nilable(String), default: nil
    const :opencode_session_id, T.nilable(String), default: nil
    const :opencode_authorization_file, T.nilable(String), default: nil
    const :capability_secret_file, T.nilable(String), default: nil

    sig { returns(Configuration) }
    def self.from_env
      new(
        heartbeat_dir: ENV.fetch("HEARTBEAT_DIR", DEFAULT_HEARTBEAT_DIR),
        opencode_url: ENV["OPENCODE_URL"],
        opencode_session_id: ENV["OPENCODE_SESSION_ID"],
        opencode_authorization_file: ENV["OPENCODE_AUTHORIZATION_FILE"],
        capability_secret_file: ENV["FUTURE_TASK_CAPABILITY_SECRET_FILE"]
      )
    end
  end
end

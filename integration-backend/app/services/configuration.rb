# typed: strict
# frozen_string_literal: true

module Services
  # Kirei owns only future commitments. Commander runtime credentials and the
  # production delivery transport are operator-managed and deliberately absent.
  class Configuration < T::Struct
    extend T::Sig

    DEFAULT_HEARTBEAT_DIR = "/tmp"

    const :heartbeat_dir, String, default: DEFAULT_HEARTBEAT_DIR

    sig { returns(Configuration) }
    def self.from_env = new(heartbeat_dir: ENV.fetch("HEARTBEAT_DIR", DEFAULT_HEARTBEAT_DIR))
  end
end

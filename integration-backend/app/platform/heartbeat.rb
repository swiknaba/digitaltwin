# typed: strict
# frozen_string_literal: true

module Platform
  # Liveness marker for processes that expose no HTTP port. Docker only restarts
  # an exited container; the file mtime lets `bin/health` also detect a process
  # that is alive but no longer progressing. `bin/health` reads the same
  # `HEARTBEAT_DIR` without booting the application.
  class Heartbeat
    extend T::Sig

    DEFAULT_DIR = "/tmp"

    sig { params(role: Role).void }
    def self.touch(role:)
      FileUtils.touch(path(role: role))
    end

    sig { params(role: Role).returns(String) }
    def self.path(role:)
      File.join(ENV.fetch("HEARTBEAT_DIR", DEFAULT_DIR), "digitaltwin-#{role.serialize}.heartbeat")
    end
  end
end

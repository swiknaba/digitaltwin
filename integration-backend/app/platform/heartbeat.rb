# typed: strict
# frozen_string_literal: true

module Platform
  # Liveness marker for processes that expose no HTTP port. Docker only restarts
  # an exited container; the file mtime lets `bin/health` also detect a process
  # that is alive but no longer progressing. The caller passes the configured
  # `HEARTBEAT_DIR`; `bin/health` reads the same variable without booting the
  # application.
  class Heartbeat
    extend T::Sig

    sig { params(role: Role, dir: String).void }
    def self.touch(role:, dir:)
      FileUtils.touch(path(role: role, dir: dir))
    end

    sig { params(role: Role, dir: String).returns(String) }
    def self.path(role:, dir:)
      File.join(dir, "digitaltwin-#{role.serialize}.heartbeat")
    end
  end
end

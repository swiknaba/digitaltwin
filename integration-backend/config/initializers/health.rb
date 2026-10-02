# typed: strict
# frozen_string_literal: true

require "json"
module Health
  extend T::Sig

  sig { params(role: String).void }
  def self.touch(role)
    path = "/tmp/digitaltwin-#{role}.json"
    tmp = "#{path}.#{Process.pid}"
    File.write(tmp, JSON.generate({ pid: Process.pid, at: Time.now.to_f }))
    File.rename(tmp, path)
  end
end

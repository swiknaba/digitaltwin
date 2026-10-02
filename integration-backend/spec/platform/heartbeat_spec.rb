# typed: false
# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe Platform::Heartbeat do
  around do |example|
    Dir.mktmpdir("heartbeat") do |dir|
      previous = ENV.fetch("HEARTBEAT_DIR", nil)
      ENV["HEARTBEAT_DIR"] = dir
      @dir = dir
      example.run
    ensure
      previous.nil? ? ENV.delete("HEARTBEAT_DIR") : ENV["HEARTBEAT_DIR"] = previous
    end
  end

  it "touches a role-specific file under HEARTBEAT_DIR and the probe reads its age", :aggregate_failures do
    path = File.join(@dir, "digitaltwin-worker.heartbeat")
    probe = File.expand_path("../../bin/health", __dir__)

    expect(system(probe, "worker")).to be(false)

    described_class.touch(role: described_class::Role::Worker)

    expect(described_class.path(role: described_class::Role::Worker)).to eq(path)
    expect(File.exist?(path)).to be(true)
    expect(system(probe, "worker")).to be(true)

    File.utime(Time.now - 120, Time.now - 120, path)
    expect(system(probe, "worker")).to be(false)
  end
end

# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe "Zeitwerk layout" do
  it "eager loads every Zeitwerk loader in a fresh backend process" do
    output, status = Open3.capture2e({ "RACK_ENV" => "test" }, "bundle", "exec", "ruby", "bin/check-zeitwerk")

    expect(status.success?).to be(true), output
    expect(output).to include("Zeitwerk eager load verified")
  end
end

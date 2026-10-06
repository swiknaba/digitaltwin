# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe "Zeitwerk layout" do
  it "eager loads the production application and checks source ownership in a fresh process" do
    output, status = Open3.capture2e({ "RACK_ENV" => "test" }, "bundle", "exec", "ruby", "bin/check-zeitwerk")

    expect(status.success?).to be(true), output
    expect(output).to include("Zeitwerk eager load and constant ownership verified")
  end
end

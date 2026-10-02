# typed: strict
# frozen_string_literal: true

RSpec.describe "application require conventions" do
  it "does not explicitly require dependencies in application source" do
    application_files = Dir[File.expand_path("../../app/**/*.rb", __dir__)]
    files_with_requires = application_files.select do |file|
      File.foreach(file).any? { |line| line.start_with?("require ") }
    end

    expect(files_with_requires).to be_empty
  end

  it "does not opt dependencies out of Bundler group loading" do
    gemfile = File.read(File.expand_path("../../Gemfile", __dir__))

    expect(gemfile).not_to include("require: false")
  end
end

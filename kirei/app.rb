# typed: true
# frozen_string_literal: true

# First: check if all gems are installed correctly
require "bundler/setup"

# Second: load all gems
#         we have runtime/production ("default") and development gems ("development")
Bundler.require(:default)
Bundler.require(:development) if ENV["RACK_ENV"] == "development"
Bundler.require(:test) if ENV["RACK_ENV"] == "test"

# Third: load all initializers
Dir[File.join(__dir__, "config/initializers", "*.rb")].each { require(_1) }

# Fourth: load all application code
APP_LOADER = Zeitwerk::Loader.new
APP_LOADER.tag = File.basename(__FILE__, ".rb")
[
  "/app",
  "/app/models",
  "/app/services",
].each do |root_namespace|
  # a root namespace skips the auto-infered module for this folder
  # so we don't have to write e.g. `Models::` or `Services::`
  APP_LOADER.push_dir("#{File.dirname(__FILE__)}#{root_namespace}")
end
APP_LOADER.setup

# Fifth: load configs
Dir[File.join(__dir__, "config", "**", "*.rb")].each do |cnf|
  next if cnf.split("/").include?("initializers")
  next if cnf.end_with?("puma.rb") # Puma config uses DSL only available when loaded by Puma

  require(cnf)
end

class Digitaltwin < Kirei::App
  # Kirei configuration
  config.app_name = "digitaltwin"
end

APP_LOADER.eager_load

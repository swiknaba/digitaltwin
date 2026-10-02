# typed: strict
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
APP_ROOT = T.let(T.must(__dir__), String)
APP_LOADER = Zeitwerk::Loader.new
APP_LOADER.tag = File.basename(__FILE__, ".rb")
# every application class lives in a domain: `app/domains/<domain>/` maps to `Domains::<Domain>`
APP_LOADER.push_dir("#{File.dirname(__FILE__)}/app")
APP_LOADER.setup

# Fifth: load configs
Dir[File.join(__dir__, "config", "**", "*.rb")].each do |cnf|
  next if cnf.split("/").include?("initializers")
  next if cnf.end_with?("puma.rb") # Puma config uses DSL only available when loaded by Puma

  require(cnf)
end

class Digitaltwin < Kirei::App
  extend T::Sig

  # Kirei configuration
  config.app_name = "digitaltwin"
  config.sensitive_keys += [/text|body|authorization|credential/i]

  sig { params(env: RequestLocalRouter::Environment).returns(RackBoundary::Response) }
  def call(env)
    RackCompatibility.new(super_method_app).call(env)
  end

  sig { returns(Method) }
  private def super_method_app
    parent = method(:call).super_method
    raise "Kirei application call handler is unavailable" unless parent

    parent
  end
end

APP_LOADER.eager_load

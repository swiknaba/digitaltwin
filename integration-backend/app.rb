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

  # Internal callbacks carry small JSON payloads; this backend receives no uploads.
  config.max_request_body_bytes = 65_536

  # Falcon serves requests on fibers; Sequel must key connection ownership by fiber.
  config.db_global_extensions = [:fiber_concurrency]
  config.db_max_connections = Integer(ENV.fetch("DB_POOL_SIZE", "5"))
  config.db_pool_timeout = Float(ENV.fetch("DB_POOL_TIMEOUT", "2"))
  config.db_connect_timeout = 5
  config.db_connect_sqls = ["SET statement_timeout = '10s'", "SET lock_timeout = '2s'"]
  unless config.db_max_connections.to_i.positive? && config.db_pool_timeout.to_f.positive?
    raise ArgumentError, "DB_POOL_SIZE and DB_POOL_TIMEOUT must be positive"
  end
end

APP_LOADER.eager_load

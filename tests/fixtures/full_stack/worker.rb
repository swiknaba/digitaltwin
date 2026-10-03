# typed: strict
# frozen_string_literal: true

require "uri"
project = ENV.fetch("DIGITALTWIN_DISPOSABLE_TEST_PROJECT")
abort "Disposable fixture project required" unless project.match?(/\Adigitaltwin-integration-[0-9a-f]{12}\z/)
abort "Fixture requires test environment" unless ENV.fetch("RACK_ENV") == "test"
abort "Disposable database required" unless URI(ENV.fetch("DATABASE_URL")).path == "/digitaltwin_development"
sleep 0.1 until File.exist?("/auth/ready")
abort "Fixture volume owner mismatch" unless File.read("/auth/ready") == project
require "/app/app"
require_relative "dispatch_policy"
require_relative "observed_herdr"
require_relative "composition"
Startup.validate!
abort "Production policy opened" if Domains::Workflows::Policy.new.dispatch_allowed?
Async do
  composition = FullStackFixture::Composition.new(configuration: Services::Configuration.from_env)
  handlers = Services::JobHandlers.new(composition: composition).call
  handlers[Platform::Jobs::Dto::JobKind::MattermostPost] = composition.deliver_outbox
  Domains::Sessions::Renewals.new.schedule_active
  Platform::Jobs::Worker.new(handlers: handlers).run(heartbeat_dir: composition.configuration.heartbeat_dir)
ensure
  Kirei::App.raw_db_connection.disconnect
end.wait

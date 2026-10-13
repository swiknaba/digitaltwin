# frozen_string_literal: true

ENV["RACK_ENV"] = "test"
ENV["APP_VERSION"] = "test"
require_relative "../app"
require "rspec"
require "async"
require "tmpdir"
require "open3"
Sequel.extension(:migration)

# Production boundaries intentionally use nominal Sorbet interfaces. RSpec's
# anonymous doubles cannot include those interfaces, even when each expected
# message is explicitly stubbed. Keep that fixture limitation scoped to
# parameter validation in the test process; return values and every concrete
# production value are still checked by sorbet-runtime.
T::Configuration.call_validation_error_handler = lambda do |_signature, options|
  value = options.fetch(:value)
  next if options.fetch(:kind) == "Parameter" && value.is_a?(RSpec::Mocks::Double)

  raise TypeError, options.fetch(:pretty_message)
end

# Wraps a spec lambda as a job handler; production handlers are use cases.
class SpecHandler
  include Platform::Jobs::Handler

  def initialize(callable)
    @callable = callable
  end

  def call(job:) = @callable.call(job)
end

# Drives real Store/Worker paths. Other kinds' jobs are pushed past the
# claim horizon so the next claim selects a job of the requested kind.
module JobFixtures
  def claim_job(kind)
    Kirei::App.raw_db_connection[:jobs].exclude(kind: kind.serialize).update(available_at: Time.now + 3600)
    Platform::Jobs::Store.new.claim(worker_id: "fixture")
  end

  def tick_job(kind, &handler)
    Kirei::App.raw_db_connection[:jobs].exclude(kind: kind.serialize).update(available_at: Time.now + 3600)
    worker = Platform::Jobs::Worker.new(handlers: { kind => SpecHandler.new(handler) })
    Async { worker.tick }.wait
  end
end

RSpec.configure do |config|
  config.include JobFixtures
  config.before do
    tables = %i[future_task_dispositions future_task_delivery_attempts future_task_executions future_tasks jobs]
    Kirei::App.raw_db_connection.run("TRUNCATE #{tables.join(",")} RESTART IDENTITY CASCADE")
  end
  config.before(:suite) do
    url = ENV.fetch("DATABASE_URL")
    raise "Use disposable digitaltwin_backend_test" unless URI(url).path == "/digitaltwin_backend_test"

    Sequel::IntegerMigrator.run(Kirei::App.raw_db_connection, File.expand_path("../db/migrate", __dir__))
  end
end

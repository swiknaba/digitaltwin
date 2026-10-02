# frozen_string_literal: true

ENV["RACK_ENV"] = "test"
ENV["APP_VERSION"] = "test"
require_relative "../app"
require "rspec"
require "async"
require "tmpdir"
require "open3"
Sequel.extension(:migration)

RSpec.configure do |config|
  config.before do
    tables = %i[master_requests session_operations workflow_requests followups conversation_bindings callbacks sessions approvals reviews queued_messages workflows projects outbox inbox audit jobs chat_checkpoints confirmations]
    Kirei::App.raw_db_connection.run("TRUNCATE #{tables.join(",")} RESTART IDENTITY CASCADE")
  end
  config.before(:suite) do
    url = ENV.fetch("DATABASE_URL")
    raise "Use disposable digitaltwin_backend_test" unless URI(url).path == "/digitaltwin_backend_test"

    Sequel::IntegerMigrator.run(Kirei::App.raw_db_connection, File.expand_path("../db/migrate", __dir__))
  end
end

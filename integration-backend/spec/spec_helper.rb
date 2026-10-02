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

# Drives real Store/Worker paths. Other kinds' jobs are pushed past the
# claim horizon so the next claim selects a job of the requested kind.
module JobFixtures
  def claim_job(kind)
    Kirei::App.raw_db_connection[:jobs].exclude(kind: kind.serialize).update(available_at: Time.now + 3600)
    Platform::Jobs::Store.new.claim(worker_id: "fixture")
  end

  def tick_job(kind, &handler)
    Kirei::App.raw_db_connection[:jobs].exclude(kind: kind.serialize).update(available_at: Time.now + 3600)
    worker = Platform::Jobs::Worker.new(handlers: { kind => Platform::Jobs::CallableHandler.new(handler) })
    Async { worker.tick }.wait
  end
end

# Builds Herdr DTOs from the wire-shaped hashes the specs describe. Missing
# conversation fields default to fixture values, so a partial identity still
# differs from any stored conversation.
module HerdrFixtures
  def herdr_pane(fields = {})
    session = fields["agent_session"]
    Adapters::Herdr::Dto::Pane.new(
      pane_id: fields.fetch("pane_id", "pane"), name: fields["name"], cwd: fields["cwd"], agent: fields["agent"],
      agent_status: Adapters::Herdr::Dto::AgentStatus.deserialize(fields.fetch("agent_status", "idle")),
      agent_session: session && herdr_session(session), interactive_ready: fields["interactive_ready"], launch_pending: fields["launch_pending"]
    )
  end

  def herdr_session(fields)
    Adapters::Herdr::Dto::AgentSession.new(source: fields.fetch("source", "fixture"), agent: fields.fetch("agent", "fixture"),
                                           kind: fields.fetch("kind", "id"), value: fields.fetch("value", "fixture"))
  end

  def herdr_workspace(workspace_id:, pane_id:)
    Adapters::Herdr::Dto::Workspace.new(workspace_id: workspace_id, root_pane_id: pane_id)
  end
end

# Stored workflows need typed role configurations; the column default {} is
# not a valid workflow (Domains::Workflows::Records fails closed on it).
module WorkflowFixtures
  WORKFLOW_ROLES = {
    "writer" => { "cli" => "codex", "provider" => "openai", "model" => "fixture-gpt", "family" => "gpt", "launch_args" => [] },
    "reviewer" => { "cli" => "claude", "provider" => "anthropic", "model" => "fixture-claude", "family" => "claude", "launch_args" => [] }
  }.freeze

  def workflow_roles = Sequel.pg_jsonb(WORKFLOW_ROLES)

  # Stored sessions need a complete RoleConfig (Domains::Sessions::Records
  # fails closed). The controller fixture reuses the Writer entry.
  def session_configuration(role = "writer") = Sequel.pg_jsonb(WORKFLOW_ROLES.fetch(role == "controller" ? "writer" : role))
end

RSpec.configure do |config|
  config.include JobFixtures
  config.include HerdrFixtures
  config.include WorkflowFixtures
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

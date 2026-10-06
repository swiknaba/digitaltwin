# frozen_string_literal: true

require_relative "../../spec_helper"
require_relative "../../support/spec_support/agentsview_usage/fixture_authorizer"
require_relative "../../support/spec_support/agentsview_usage/fixture_runner"
require "date"
require "open3"
require "stringio"
require "timeout"

RSpec.describe Adapters::Mcp::AgentsviewUsageServer do
  def usage_document(cost_source: "computed", amount: 23, matched_pattern: "gpt-5.1", tokens: 10, models: true)
    {
      "schema_version" => 6,
      "pricing" => {
        "source" => "embedded",
        "table_version" => "fixture",
        "latest_row_updated_at" => nil,
        "cost_source" => cost_source,
        "fallback" => { "used" => true },
        "models" => models ? {
          "gpt-5.1" => {
            "cost_source" => cost_source,
            "resolutions" => [{ "matched_pattern" => matched_pattern, "cost_source" => cost_source }]
          }
        } : {}
      },
      "totals" => {
        "inputTokens" => tokens,
        "outputTokens" => tokens.zero? ? 0 : 2,
        "cacheCreationTokens" => tokens.zero? ? 0 : 3,
        "cacheReadTokens" => tokens.zero? ? 0 : 4,
        "totalCost" => { "microdollars" => amount }
      }
    }
  end

  def response_for(
    arguments,
    document: usage_document,
    timezone: "Europe/Berlin",
    source_roots: nil,
    managed_config_path: nil,
    active_config_path: nil,
    authorizer: usage_authorizer { |_token| }
  )
    calls = []
    runner = SpecSupport::AgentsviewUsage::FixtureRunner.new do |environment, argv|
      calls << [environment, argv]
      argv[1] == "sync" ? "" : JSON.generate(document)
    end
    Dir.mktmpdir do |dir|
      roots = source_roots || begin
        created = %w[codex claude gemini opencode].map { |name| File.join(dir, name) }
        created.each { |path| Dir.mkdir(path) }
        created.map { |path| File.realpath(path) }
      end
      command = Adapters::Mcp::AgentsviewUsageCommand.new(
        timezone: timezone, command_runner: runner, source_roots: roots,
        managed_config_path: managed_config_path, active_config_path: active_config_path, authorizer: authorizer
      )
      token = File.join(dir, "request-token")
      File.write(token, "fixture-capability")
      input = StringIO.new(JSON.generate(jsonrpc: "2.0", id: 1, method: "tools/list") + "\n" + JSON.generate(jsonrpc: "2.0", id: 2, method: "tools/call", params: { name: "get_usage", arguments: arguments }) + "\n")
      output = StringIO.new
      described_class.new(command: command, token_file: token).serve(input: input, output: output)
      rows = output.string.lines.map { |line| JSON.parse(line) }
      [rows, calls]
    end
  end

  def usage_authorizer(&implementation)
    SpecSupport::AgentsviewUsage::FixtureAuthorizer.new(&implementation)
  end

  it "exposes exactly the safe usage tool and runs only fixed local commands" do
    rows, calls = response_for({ "range" => { "dates" => { "from" => "2026-10-04", "to" => "2026-10-05" } }, "agent" => "codex" })

    expect(rows.first.dig("result", "tools").map { |tool| tool.fetch("name") }).to eq(["get_usage"])
    value = JSON.parse(rows.last.dig("result", "content", 0, "text"))
    expect(value).to include(
      "range" => { "kind" => "dates", "from" => "2026-10-04", "to" => "2026-10-05", "timezone" => "Europe/Berlin" },
      "agent" => "codex",
      "tokens" => { "input" => 10, "output" => 2, "cache_creation" => 3, "cache_read" => 4 },
      "cost" => { "status" => "estimated_api", "microdollars" => 23 }
    )
    expect(value.fetch("source")).to eq({ "machine" => "runtime", "archive_freshness" => "synced" })
    environment = {
      "AGENTSVIEW_NO_DAEMON" => "1", "AGENTSVIEW_DATA_DIR" => "/home/runtime/.agentsview",
      "CLAUDE_PROJECTS_DIR" => "/home/runtime/.claude/projects", "CODEX_SESSIONS_DIR" => "/home/runtime/.codex/sessions",
      "GEMINI_DIR" => "/home/runtime/.gemini", "OPENCODE_DIR" => "/home/runtime/.local/share/opencode"
    }
    expected_calls = [
      [environment, ["/usr/local/bin/agentsview", "sync"]],
      [environment, ["/usr/local/bin/agentsview", "usage", "daily", "--json", "--offline", "--no-sync", "--breakdown", "--timezone", "Europe/Berlin", "--since", "2026-10-04", "--until", "2026-10-05", "--agent", "codex"]]
    ]
    expect(calls).to eq(expected_calls)
  end

  it "preserves a reported zero and never serializes missing token data as zero cost" do
    reported_zero = usage_document(cost_source: "reported", amount: 0, matched_pattern: nil, tokens: 0, models: false)
    rows, = response_for({ "range" => { "today" => true } }, document: reported_zero, timezone: "UTC")
    reported = JSON.parse(rows.last.dig("result", "content", 0, "text"))
    expect(reported.fetch("cost")).to eq({ "status" => "reported", "microdollars" => 0 })

    unavailable = usage_document(amount: 0, tokens: 0)
    rows, = response_for({ "range" => { "today" => true } }, document: unavailable, timezone: "UTC")
    value = JSON.parse(rows.last.dig("result", "content", 0, "text"))
    expect(value.fetch("cost")).to eq({ "status" => "unavailable" })

    mixed = usage_document(cost_source: "mixed", amount: 5)
    rows, = response_for({ "range" => { "today" => true } }, document: mixed, timezone: "UTC")
    value = JSON.parse(rows.last.dig("result", "content", 0, "text"))
    expect(value.fetch("cost")).to eq({ "status" => "mixed", "microdollars" => 5 })
  end

  it "marks unpriced token rows as a partial estimate and accepts the supported calendar forms" do
    partial = usage_document(amount: 11, matched_pattern: nil)
    rows, = response_for({ "range" => { "last_days" => 2 } }, document: partial, timezone: "UTC")
    value = JSON.parse(rows.last.dig("result", "content", 0, "text"))
    expect(value.fetch("cost")).to eq({ "status" => "partial_estimate", "microdollars" => 11 })

    rows, = response_for({ "range" => { "current_month" => true } }, timezone: "UTC")
    range = JSON.parse(rows.last.dig("result", "content", 0, "text")).fetch("range")
    expect(range.fetch("from")).to match(/\A\d{4}-\d{2}-01\z/)
    expect(range.fetch("to")).to match(/\A\d{4}-\d{2}-\d{2}\z/)
  end

  it "rejects malformed ranges, unknown fields, unsupported agents, and invalid timezones before a command runs" do
    invalid_arguments = [
      { "range" => { "today" => true, "current_month" => true } },
      { "range" => { "last_days" => 0 } },
      { "range" => { "dates" => { "from" => "2026-10-05T01:00:00Z", "to" => "2026-10-05" } } },
      { "range" => { "today" => true }, "agent" => "claude,gemini" },
      { "range" => { "today" => true }, "command" => "cat" }
    ]
    invalid_arguments.each do |arguments|
      rows, calls = response_for(arguments)
      expect(rows.last.dig("error", "code")).to eq(-32_602)
      expect(calls).to be_empty
    end
    expect { Adapters::Mcp::AgentsviewUsageCommand.new(timezone: "../../../etc/passwd", authorizer: usage_authorizer { |_token| }) }.to raise_error(ArgumentError)
  end

  it "requires a live request capability before touching source roots or AgentsView" do
    rejected = usage_authorizer { |_token| raise IOError, "rejected fixture capability" }
    rows, calls = response_for({ "range" => { "today" => true } }, authorizer: rejected)

    expect(rows.last.dig("error", "code")).to eq(-32_602)
    expect(calls).to be_empty
  end

  it "fails closed when any fixed source root is missing" do
    missing = File.join(Dir.tmpdir, "agentsview-missing-root-#{Process.pid}")
    rows, calls = response_for({ "range" => { "today" => true } }, source_roots: [missing])

    expect(rows.last.dig("error", "code")).to eq(-32_602)
    expect(calls).to be_empty
  end

  it "fails closed when a fixed source root is a symlink" do
    Dir.mktmpdir do |dir|
      target = File.join(dir, "target")
      link = File.join(dir, "link")
      Dir.mkdir(target)
      File.symlink(target, link)
      rows, calls = response_for({ "range" => { "today" => true } }, source_roots: [link])

      expect(rows.last.dig("error", "code")).to eq(-32_602)
      expect(calls).to be_empty
    end
  end

  it "fails closed when the managed local-only configuration changes" do
    Dir.mktmpdir do |dir|
      expected = File.join(dir, "expected.toml")
      active = File.join(dir, "active.toml")
      File.write(expected, "archive_content = \"usage\"\n")
      File.write(active, "[[remote_hosts]]\nhost = \"example.invalid\"\n")
      rows, calls = response_for({ "range" => { "today" => true } }, managed_config_path: expected, active_config_path: active)

      expect(rows.last.dig("error", "code")).to eq(-32_602)
      expect(calls).to be_empty
    end
  end

  it "does not alter the ordinary Commander bridge mode" do
    Dir.mktmpdir do |dir|
      token = File.join(dir, "token")
      File.write(token, "disposable-fixture")
      input = JSON.generate(jsonrpc: "2.0", id: 1, method: "initialize") + "\n"
      output, status = Open3.capture2e({ "DIGITALTWIN_CALLBACK_URL" => "http://127.0.0.1:9", "DIGITALTWIN_COMMANDER_REQUEST_TOKEN_FILE" => token }, "ruby", "bin/mcp", stdin_data: input)
      expect(status.success?).to be(true), output
      expect(JSON.parse(output).dig("result", "serverInfo", "name")).to eq("digitaltwin")
    end
  end
end

# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe Services::Commander::Memory do
  let(:db) { Kirei::App.raw_db_connection }

  around do |example|
    Dir.mktmpdir("digitaltwin-memory") do |root|
      @commander_workspace = File.join(root, "commander")
      @project_workspace = File.join(root, "project")
      FileUtils.mkdir_p([@commander_workspace, @project_workspace])
      example.run
    end
  end

  before do
    db[:projects].insert(id: "project", channel_id: "project-channel", slug: "owner/repository", remote_identity: "github.com/owner/repository", workspace: @project_workspace)
  end

  let(:memory) do
    described_class.new(
      commander_workspace: @commander_workspace,
      directory: Domains::Projects::Directory.new
    )
  end

  let(:scope) { Domains::Memory::Dto::MemoryScope }

  it "persists global preferences in Commander memory across service restarts" do
    remembered = memory.remember(
      scope: scope::Global, project_id: nil, content: "Prefer concise status reports.", source: "inbox:human-1", idempotency_key: "preference-1"
    )

    expect(remembered).to be_success
    expect(remembered.result.revision).to eq(1)
    expect(File.read(File.join(@commander_workspace, "memory.md"))).to include("Prefer concise status reports.")

    restarted = described_class.new(commander_workspace: @commander_workspace, directory: Domains::Projects::Directory.new)
    expect(restarted.read(scope: scope::Global, project_id: nil, limit: 10).result).to eq([remembered.result])
  end

  it "writes project decisions only to the enrolled project memory file" do
    remembered = memory.remember(
      scope: scope::Project, project_id: "project", content: "Use a release branch for the API change.", source: "inbox:human-2", idempotency_key: "decision-1"
    )

    expect(remembered).to be_success
    expect(remembered.result.project_id).to eq("project")
    expect(File.read(File.join(@project_workspace, ".agents", "memory.md"))).to include("Use a release branch for the API change.")
    commander_memory = File.join(@commander_workspace, "memory.md")
    expect(File.exist?(commander_memory) ? File.read(commander_memory) : "").not_to include("release branch")
  end

  it "corrects exactly one entry with optimistic revision protection" do
    entry = memory.remember(
      scope: scope::Global, project_id: nil, content: "Use the staging database.", source: "inbox:human-3", idempotency_key: "preference-2"
    ).result

    corrected = memory.correct(
      id: entry.id, expected_revision: entry.revision, content: "Use the disposable test database.", source: "inbox:human-4", idempotency_key: "correction-1"
    )
    stale = memory.correct(
      id: entry.id, expected_revision: entry.revision, content: "This stale change must fail.", source: "inbox:human-5", idempotency_key: "correction-2"
    )

    expect(corrected.result.revision).to eq(2)
    expect(corrected.result.source).to eq("inbox:human-4")
    expect(stale.errors.first.code).to eq("revision_changed")
    expect(File.read(File.join(@commander_workspace, "memory.md"))).to include("Use the disposable test database.")
    expect(File.read(File.join(@commander_workspace, "memory.md"))).not_to include("This stale change")
  end

  it "makes duplicate requests idempotent without duplicating the rendered entry" do
    arguments = {
      scope: scope::Global, project_id: nil, content: "Keep review evidence with the artifact.", source: "inbox:human-6", idempotency_key: "preference-3"
    }

    first = memory.remember(**arguments)
    repeated = memory.remember(**arguments)

    expect(repeated.result).to eq(first.result)
    expect(memory.read(scope: scope::Global, project_id: nil, limit: 10).result.length).to eq(1)
    expect(File.read(File.join(@commander_workspace, "memory.md")).scan("Keep review evidence with the artifact.").length).to eq(1)
  end

  it "serializes concurrent writes for one memory scope" do
    results = Queue.new
    threads = 2.times.map do |index|
      Thread.new do
        results << memory.remember(
          scope: scope::Global, project_id: nil, content: "Preference #{index}", source: "inbox:human-#{index}", idempotency_key: "concurrent-#{index}"
        )
      end
    end
    threads.each(&:join)

    outcomes = 2.times.map { results.pop }
    expect(outcomes).to all(be_success)
    expect(memory.read(scope: scope::Global, project_id: nil, limit: 10).result.map(&:content)).to contain_exactly("Preference 0", "Preference 1")
  end

  it "fails closed when a project memory request names no enrolled project" do
    outcome = memory.remember(
      scope: scope::Project, project_id: "missing", content: "Never write this.", source: "inbox:human-7", idempotency_key: "missing-project"
    )

    expect(outcome.errors.first.code).to eq("missing_project")
    expect(File.exist?(File.join(@commander_workspace, "memory.md"))).to be(false)
  end

  it "rejects a project binding supplied for global memory" do
    outcome = memory.remember(
      scope: scope::Global, project_id: "project", content: "Never write this globally.", source: "inbox:human-8", idempotency_key: "invalid-global"
    )

    expect(outcome.errors.first.code).to eq("missing_project")
  end
end

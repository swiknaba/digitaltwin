# frozen_string_literal: true

require "rspec"
require "sequel"
require "open3"
require "uri"

RSpec.describe "Clean application migration entrypoint" do
  def annotated_entities
    %w[
      app/domains/commander/entities/commander_request.rb
      app/domains/commander/entities/confirmation.rb
      app/domains/commander/entities/followup.rb
      app/domains/memory/entities/memory_entry.rb
      app/domains/memory/entities/memory_operation.rb
      app/domains/reviews/entities/review.rb
      app/domains/sessions/entities/runtime_session.rb
      app/domains/workflows/entities/workflow.rb
      app/domains/workflows/entities/workflow_request.rb
    ]
  end

  it "runs the real rake command from an empty database without application or JSON helper preload" do
    url = ENV.fetch("MIGRATION_TEST_DATABASE_URL")
    raise "Use disposable digitaltwin_migration_test" unless URI(url).path == "/digitaltwin_migration_test"

    db = Sequel.connect(url)
    db.run("DROP SCHEMA public CASCADE")
    db.run("CREATE SCHEMA public")
    expect(db.tables).to be_empty
    root = File.expand_path("../..", __dir__)
    annotations = annotated_entities.to_h { |path| [path, File.read(File.join(root, path))] }
    env = { "DATABASE_URL" => url, "RACK_ENV" => "test", "NO_LOGS" => "true" }
    output, status = Open3.capture2e(env, "bundle", "exec", "rake", "db:migrate", chdir: root)
    expect(status.success?).to be(true), output
    expect(db[:schema_info].get(:version)).to eq(9)
    expect(db.tables).to include(:jobs, :projects, :sessions, :workflows, :reviews, :confirmations, :memory_entries, :memory_operations)
    annotated_entities.each do |path|
      expect(File.read(File.join(root, path))).to eq(annotations.fetch(path)), "db:migrate changed generated annotation #{path}"
    end
    output, status = Open3.capture2e(env, "bundle", "exec", "rake", "db:migrate", chdir: root)
    expect(status.success?).to be(true), output
    expect(db[:schema_info].get(:version)).to eq(9)
    output, status = Open3.capture2e(env.merge("STEPS" => "9"), "bundle", "exec", "rake", "db:rollback", chdir: root)
    expect(status.success?).to be(true), output
    expect(db[:schema_info].get(:version)).to eq(0)
    output, status = Open3.capture2e(env, "bundle", "exec", "rake", "db:migrate", chdir: root)
    expect(status.success?).to be(true), output
    expect(db[:schema_info].get(:version)).to eq(9)
  ensure
    db&.disconnect
  end
end

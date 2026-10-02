# frozen_string_literal: true

require "rspec"
require "sequel"
require "open3"
require "uri"

RSpec.describe "Clean application migration entrypoint" do
  it "runs the real rake command from an empty database without application or JSON helper preload" do
    url = ENV.fetch("MIGRATION_TEST_DATABASE_URL")
    raise "Use disposable digitaltwin_migration_test" unless URI(url).path == "/digitaltwin_migration_test"

    db = Sequel.connect(url)
    db.run("DROP SCHEMA public CASCADE")
    db.run("CREATE SCHEMA public")
    expect(db.tables).to be_empty
    root = File.expand_path("../..", __dir__)
    env = { "DATABASE_URL" => url, "RACK_ENV" => "test", "NO_LOGS" => "true" }
    output, status = Open3.capture2e(env, "bundle", "exec", "rake", "db:migrate", chdir: root)
    expect(status.success?).to be(true), output
    expect(db[:schema_info].get(:version)).to eq(7)
    expect(db.tables).to include(:jobs, :projects, :sessions, :workflows, :reviews, :confirmations)
    output, status = Open3.capture2e(env, "bundle", "exec", "rake", "db:migrate", chdir: root)
    expect(status.success?).to be(true), output
    expect(db[:schema_info].get(:version)).to eq(7)
    output, status = Open3.capture2e(env.merge("STEPS" => "7"), "bundle", "exec", "rake", "db:rollback", chdir: root)
    expect(status.success?).to be(true), output
    expect(db[:schema_info].get(:version)).to eq(0)
    output, status = Open3.capture2e(env, "bundle", "exec", "rake", "db:migrate", chdir: root)
    expect(status.success?).to be(true), output
    expect(db[:schema_info].get(:version)).to eq(7)
  ensure
    db&.disconnect
  end
end

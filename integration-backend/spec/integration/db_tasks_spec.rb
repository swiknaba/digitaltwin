# frozen_string_literal: true

require "rspec"
require "rake"
require "sequel"
require "tmpdir"
require "fileutils"
require "stringio"
require "uri"

RSpec.describe "Numbered database migration tasks" do
  before(:all) do
    @url = ENV.fetch("MIGRATION_TEST_DATABASE_URL")
    # This suite removes its fixture tables. Never run it against application data.
    raise "Use the disposable digitaltwin_migration_test database" unless URI(@url).path == "/digitaltwin_migration_test"

    @db = Sequel.connect(@url)
  end

  after(:all) { @db&.disconnect }

  around do |example|
    old_rake = Rake.application
    old_env = ENV.to_h.slice("DATABASE_URL", "RACK_ENV", "STEPS")
    Dir.mktmpdir("digitaltwin-migrations") do |root|
      @root = root
      FileUtils.mkdir_p("#{root}/lib/tasks")
      FileUtils.mkdir_p("#{root}/db/migrate")
      FileUtils.cp(File.expand_path("../../lib/tasks/db.rake", __dir__), "#{root}/lib/tasks/db.rake")
      # Exercise the real Rake tasks with a small bootstrap interface and live DB.
      # This fixture does not test application startup or its required Ruby version.
      File.write("#{root}/app.rb", <<~RUBY)
        class Digitaltwin
          def self.root = #{root.inspect}
          def self.default_db_url = ENV.fetch("DATABASE_URL")
          def self.raw_db_connection = @raw_db_connection ||= Sequel.connect(default_db_url)
        end
      RUBY
      @db.tables.grep(/\A(?:migration_fixture_\d+|schema_info|schema_migrations)\z/).each { |table|
        @db.drop_table(table)
      }
      ENV["DATABASE_URL"] = @url
      ENV["RACK_ENV"] = "test"
      ENV.delete("STEPS")
      Rake.application = Rake::Application.new
      load "#{root}/lib/tasks/db.rake"
      Dir.chdir(root) { example.run }
    ensure
      Digitaltwin.raw_db_connection.disconnect if defined?(Digitaltwin)
    end
  ensure
    Rake.application = old_rake
    %w[DATABASE_URL RACK_ENV STEPS].each { |key| old_env.key?(key) ? ENV[key] = old_env[key] : ENV.delete(key) }
  end

  def numbered_migrations
    %w[jobs projects sessions workflows reviews confirmations].each_with_index do |name, offset|
      version = offset + 1
      File.write("#{@root}/db/migrate/#{version.to_s.rjust(3, '0')}_#{name}.rb", <<~RUBY)
        Sequel.migration do
          up { create_table(:migration_fixture_#{version}) { primary_key :id } }
          down { drop_table(:migration_fixture_#{version}) }
        end
      RUBY
    end
  end

  def invoke(name, *args)
    Rake::Task[name].reenable
    Rake::Task["db:annotate"].reenable
    previous = $stdout
    $stdout = StringIO.new
    Rake::Task[name].invoke(*args)
    $stdout.string
  ensure
    $stdout = previous
  end

  it "migrates all six numbered files and reports integer status without timestamp metadata" do
    numbered_migrations
    expect(invoke("db:status")).to include("version: 0")
    expect(invoke("db:migrate")).to include("version 6!")
    expect(@db[:schema_info].get(:version)).to eq(6)
    expect(@db.table_exists?(:schema_migrations)).to be(false)
    expect(invoke("db:status")).to include("version: 6")
    expect(invoke("db:migrate")).to include("version 6!")
    expect(@db.tables.grep(/migration_fixture_/).length).to eq(6)
  end

  it "rolls back one or several steps, including the last migration to zero" do
    numbered_migrations
    invoke("db:migrate")
    expect(invoke("db:rollback")).to include("1 steps to version 5")
    expect(@db.table_exists?(:migration_fixture_6)).to be(false)
    ENV["STEPS"] = "2"
    expect(invoke("db:rollback")).to include("2 steps to version 3")
    ENV["STEPS"] = "10"
    expect(invoke("db:rollback")).to include("3 steps to version 0")
    expect(@db[:schema_info].get(:version)).to eq(0)
    expect(@db.tables.grep(/migration_fixture_/)).to be_empty
    expect(invoke("db:rollback")).to include("No more migrations")
  end

  it "rejects invalid rollback steps without changing the schema" do
    numbered_migrations
    invoke("db:migrate")
    %w[0 -1 invalid].each do |steps|
      ENV["STEPS"] = steps
      expect { invoke("db:rollback") }.to raise_error(ArgumentError)
      expect(@db[:schema_info].get(:version)).to eq(6)
    end
  end

  it "generates contiguous numbered filenames from an empty directory and after 006" do
    invoke("db:migration", "jobs")
    expect(File.exist?("#{@root}/db/migrate/001_jobs.rb")).to be(true)
    numbered_migrations
    invoke("db:migration", "nextChange")
    expect(File.exist?("#{@root}/db/migrate/007_next_change.rb")).to be(true)
  end
end

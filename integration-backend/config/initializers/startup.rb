# typed: strict
# frozen_string_literal: true

module Startup
  extend T::Sig

  class << self
    extend T::Sig

    sig { returns(T::Boolean) }
    def validate!
      database = Kirei::App.raw_db_connection
      expected = expected_migration_version
      current = schema_version(database)
      raise "Pending migrations: expected #{expected}, current #{current}" unless current == expected

      database.get(1)
      true
    end

    private

    sig { returns(Integer) }
    def expected_migration_version
      path = File.expand_path("../../db/migrate", __dir__)
      versions = Dir["#{path}/*.rb"].map { |name| File.basename(name).to_i }
      versions.max || 0
    end

    sig { params(database: Sequel::Database).returns(Integer) }
    def schema_version(database)
      return 0 unless database.table_exists?(:schema_info)

      Integer(database[:schema_info].get(:version))
    end
  end
end

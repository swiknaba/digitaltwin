# frozen_string_literal: true

module Startup
  def self.validate!
    db = Kirei::App.raw_db_connection
    path = File.expand_path("../../db/migrate", __dir__)
    expected = Dir["#{path}/*.rb"].map { |name| File.basename(name).to_i }.max || 0
    current = db.table_exists?(:schema_info) ? db[:schema_info].get(:version).to_i : 0
    raise "Pending migrations: expected #{expected}, current #{current}" unless current == expected

    db.get(1)
    true
  end
end

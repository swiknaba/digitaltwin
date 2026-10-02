# typed: strict

# Sequel loads its migration extension dynamically. Tapioca sees the database
# schema classes but not the extension entry point or its `change` DSL hook.
module Sequel
  extend T::Sig

  class << self
    sig { params(block: T.proc.bind(Sequel::MigrationDSL).void).returns(Sequel::SimpleMigration) }
    def migration(&block); end
  end
end

class Sequel::SimpleMigration
  extend T::Sig

  sig { params(db: Sequel::Database, direction: Symbol).void }
  def apply(db, direction); end
end

class Sequel::Database
  extend T::Sig

  sig do
    params(
      name: Symbol,
      options: T.nilable(T::Hash[Symbol, Object]),
      block: T.proc.bind(Sequel::Schema::CreateTableGenerator).void
    ).void
  end
  def create_table(name, options = nil, &block); end

  sig { params(name: Symbol, block: T.proc.bind(Sequel::Schema::AlterTableGenerator).void).void }
  def alter_table(name, &block); end
end

class Sequel::MigrationDSL
  extend T::Sig

  sig { params(block: T.proc.bind(Sequel::Database).void).void }
  def change(&block); end
end

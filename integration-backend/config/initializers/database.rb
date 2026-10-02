# typed: strict
# frozen_string_literal: true

# This is a global Sequel extension; loading it on a Database has no effect.
Sequel.extension(:fiber_concurrency, :migration)

# Sequel yields the adapter's native connection to +after_connect+. The only
# operation this application needs at that boundary is executing SQL setup.
module DatabaseSession
  extend T::Sig
  extend T::Helpers

  interface!

  sig { abstract.params(sql: String).returns(Object) }
  def exec(sql); end
end

module BoundedDatabase
  extend T::Sig

  LOCK = Mutex.new
  @connection = T.let(nil, T.nilable(Sequel::Database))

  class << self
    extend T::Sig

    sig { returns(Sequel::Database) }
    def connection
      existing = @connection
      return existing unless existing.nil?

      LOCK.synchronize do
        @connection ||= build_connection
      end
    end

    private

    sig { returns(Sequel::Database) }
    def build_connection
      size = Integer(ENV.fetch("DB_POOL_SIZE", "5"))
      timeout = Float(ENV.fetch("DB_POOL_TIMEOUT", "2"))
      raise ArgumentError, "Invalid DB pool bounds" unless size.positive? && timeout.positive?

      configure = T.let(
        lambda do |connection|
          connection.exec("SET statement_timeout = '10s'; SET lock_timeout = '2s'")
        end,
        T.proc.params(connection: DatabaseSession).void
      )
      database = Sequel.connect(
        ENV.fetch("DATABASE_URL"),
        max_connections: size,
        pool_timeout: timeout,
        connect_timeout: 5,
        after_connect: configure
      )
      database.extension(:pg_json, :pg_array)
      database
    end
  end

  sig { returns(Sequel::Database) }
  def raw_db_connection
    BoundedDatabase.connection
  end
end

Kirei::App.singleton_class.prepend(BoundedDatabase)

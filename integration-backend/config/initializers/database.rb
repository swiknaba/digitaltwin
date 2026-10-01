# frozen_string_literal: true

# This is a global Sequel extension; loading it on a Database has no effect.
Sequel.extension(:fiber_concurrency, :migration)
module BoundedDatabase
  LOCK = Mutex.new
  def raw_db_connection
    LOCK.synchronize do
      @raw_db_connection ||= begin
        size = Integer(ENV.fetch("DB_POOL_SIZE", "5"))
        timeout = Float(ENV.fetch("DB_POOL_TIMEOUT", "2"))
        raise ArgumentError, "Invalid DB pool bounds" unless size.positive? && timeout.positive?

        configure = ->(connection) do
          connection.exec("SET statement_timeout = '10s'; SET lock_timeout = '2s'")
        end
        db = Sequel.connect(ENV.fetch("DATABASE_URL"), max_connections: size, pool_timeout: timeout,
                                                       connect_timeout: 5, after_connect: configure)
        db.extension(:pg_json, :pg_array)
        db
      end
    end
  end
end
Kirei::App.singleton_class.prepend(BoundedDatabase)

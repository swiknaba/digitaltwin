# typed: strict
# frozen_string_literal: true

module Platform
  # Session-level PostgreSQL advisory lock keyed by `hashtextextended(key, 0)`.
  # Kirei has no advisory-lock API, so this uses the raw connection. The
  # connection stays checked out for the block, and the lock is released in
  # `ensure`.
  class Lock
    extend T::Sig

    sig do
      type_parameters(:R)
        .params(key: String, blk: T.proc.returns(T.type_parameter(:R)))
        .returns(T.type_parameter(:R))
    end
    def call(key:, &blk)
      db = Kirei::App.raw_db_connection
      db.synchronize do
        lock_key = Sequel.function(:hashtextextended, key, 0)
        raise Busy, "Workflow busy" unless db.get(Sequel.function(:pg_try_advisory_lock, lock_key))

        begin
          yield
        ensure
          db.get(Sequel.function(:pg_advisory_unlock, lock_key))
        end
      end
    end
  end
end

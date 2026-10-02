# frozen_string_literal: true

module Domains
  module Workflows
    class Lock
      def initialize(db) = @db = db

      def call(id)
        @db.synchronize do
          key = Sequel.function(:hashtextextended, id, 0)
          raise ArgumentError, "Workflow busy" unless @db.get(Sequel.function(:pg_try_advisory_lock, key))

          begin
            yield
          ensure
            @db.get(Sequel.function(:pg_advisory_unlock, key))
          end
        end
      end
    end
  end
end

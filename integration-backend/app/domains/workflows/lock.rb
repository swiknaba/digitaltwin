# typed: strict
# frozen_string_literal: true

module Domains
  module Workflows
    class Lock
      extend T::Sig

      sig { params(db: Sequel::Database).void }
      def initialize(db)
        @db = T.let(db, Sequel::Database)
      end

      sig do
        type_parameters(:Result)
          .params(id: String, block: T.proc.returns(T.type_parameter(:Result)))
          .returns(T.type_parameter(:Result))
      end
      def call(id, &block)
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

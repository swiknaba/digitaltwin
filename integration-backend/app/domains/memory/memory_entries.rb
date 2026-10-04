# typed: strict
# frozen_string_literal: true

module Domains
  module Memory
    # Typed persistence for source-attributed Commander memory. Callers hold a
    # scope lock while changing entries and their rendered memory file.
    class MemoryEntries
      extend T::Sig

      Scope = Dto::MemoryScope
      Entry = Dto::MemoryEntry
      MALFORMED = "Malformed durable Commander memory record"

      sig { params(scope: Scope, project_id: T.nilable(String), limit: Integer).returns(T::Array[Entry]) }
      def list(scope:, project_id:, limit: 50)
        entries(Entities::MemoryEntry.query.where(scope: scope.serialize, project_id: project_id).order(:created_at, :id).limit(limit))
      end

      sig { params(id: String).returns(T.nilable(Entry)) }
      def find(id:)
        entity = strictly { Entities::MemoryEntry.resolve_first(Entities::MemoryEntry.query.where(id: id), true) }
        entity && view(entity)
      end

      sig { params(scope: Scope, project_id: T.nilable(String), idempotency_key: String).returns(T.nilable(Entry)) }
      def for_operation(scope:, project_id:, idempotency_key:)
        operation = strictly do
          Entities::MemoryOperation.resolve_first(
            Entities::MemoryOperation.query.where(scope: scope.serialize, project_id: project_id, idempotency_key: idempotency_key), true
          )
        end
        operation && find(id: operation.entry_id)
      end

      sig { params(scope: Scope, project_id: T.nilable(String)).returns(Integer) }
      def count(scope:, project_id:)
        Entities::MemoryEntry.query.where(scope: scope.serialize, project_id: project_id).count
      end

      sig { params(scope: Scope, project_id: T.nilable(String), content: String, source: String, idempotency_key: String, now: Time).returns(Entry) }
      def create(scope:, project_id:, content:, source:, idempotency_key:, now: Time.now.utc)
        entity = Entities::MemoryEntry.create(id: SecureRandom.uuid, scope: scope.serialize, project_id: project_id, content: content, source: source,
                                              revision: 1, created_at: now, updated_at: now)
        Entities::MemoryOperation.create(id: SecureRandom.uuid, entry_id: entity.id, scope: scope.serialize, project_id: project_id,
                                         idempotency_key: idempotency_key, kind: "remember", created_at: now)
        view(entity)
      end

      sig { params(id: String, expected_revision: Integer, content: String, source: String, idempotency_key: String, now: Time).returns(T.nilable(Entry)) }
      def correct(id:, expected_revision:, content:, source:, idempotency_key:, now: Time.now.utc)
        current = find(id: id)
        return nil unless current

        changed = Entities::MemoryEntry.query.where(id: id, revision: expected_revision).update(content: content, source: source, revision: expected_revision + 1, updated_at: now)
        return nil unless changed == 1

        Entities::MemoryOperation.create(id: SecureRandom.uuid, entry_id: id, scope: current.scope.serialize, project_id: current.project_id,
                                         idempotency_key: idempotency_key, kind: "correct", created_at: now)
        T.must(find(id: id))
      end

      sig { params(query: Sequel::Dataset).returns(T::Array[Entry]) }
      private def entries(query)
        strictly { Entities::MemoryEntry.resolve(query, true) }.map { |entity| view(entity) }
      end

      sig { params(entity: Entities::MemoryEntry).returns(Entry) }
      private def view(entity)
        Entry.new(id: entity.id, scope: entity.scope, project_id: entity.project_id, content: entity.content, source: entity.source,
                  revision: entity.revision, created_at: entity.created_at, updated_at: entity.updated_at)
      end

      sig { type_parameters(:R).params(blk: T.proc.returns(T.type_parameter(:R))).returns(T.type_parameter(:R)) }
      private def strictly(&blk)
        yield
      rescue RuntimeError, KeyError, TypeError
        raise Errors::MalformedRecord, MALFORMED
      end
    end
  end
end

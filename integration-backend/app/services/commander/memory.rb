# typed: strict
# frozen_string_literal: true

module Services
  module Commander
    # Bounded, source-attributed Commander memory. Database records are
    # authoritative; the local Markdown files are atomically regenerated from
    # those records while the relevant scope lock is held.
    class Memory
      extend T::Sig

      Scope = Domains::Memory::Dto::MemoryScope
      Entry = Domains::Memory::Dto::MemoryEntry
      Code = Domains::Memory::Dto::ErrorCode
      Outcome = T.type_alias { Kirei::Services::Result[Entry] }
      ReadOutcome = T.type_alias { Kirei::Services::Result[T::Array[Entry]] }
      MAX_CONTENT_BYTES = 4_000
      MAX_ENTRIES = 100
      MAX_LIMIT = 50
      LOCK_ATTEMPTS = 10

      sig do
        params(commander_workspace: String, directory: Domains::Projects::Directory, entries: Domains::Memory::MemoryEntries,
               files: Adapters::Memory::FileStore, lock: Platform::Lock, transaction: Platform::Transaction).void
      end
      def initialize(commander_workspace: Services::Configuration::DEFAULT_COMMANDER_WORKSPACE, directory: Domains::Projects::Directory.new,
                     entries: Domains::Memory::MemoryEntries.new, files: Adapters::Memory::FileStore.new, lock: Platform::Lock.new,
                     transaction: Platform::Transaction.new)
        @commander_workspace = commander_workspace
        @directory = directory
        @entries = entries
        @files = files
        @lock = lock
        @transaction = transaction
      end

      sig { params(scope: Scope, project_id: T.nilable(String), limit: Integer).returns(ReadOutcome) }
      def read(scope:, project_id:, limit: MAX_LIMIT)
        return failure_list(Code::InvalidLimit, "Memory limit must be between 1 and #{MAX_LIMIT}") unless limit.between?(1, MAX_LIMIT)
        return failure_list(Code::MissingProject, "Memory scope requires its matching project binding") unless valid_scope_binding?(scope: scope, project_id: project_id)

        project = project(scope: scope, project_id: project_id)
        return failure_list(Code::MissingProject, "Project memory requires an enrolled project") if scope == Scope::Project && !project

        Kirei::Services::Result.new(result: @entries.list(scope: scope, project_id: project_id, limit: limit))
      end

      sig { params(scope: Scope, project_id: T.nilable(String), content: String, source: String, idempotency_key: String).returns(Outcome) }
      def remember(scope:, project_id:, content:, source:, idempotency_key:)
        attempts = T.let(0, Integer)
        return invalid_content unless valid_content?(content: content, source: source, idempotency_key: idempotency_key)
        return failure(Code::MissingProject, "Memory scope requires its matching project binding") unless valid_scope_binding?(scope: scope, project_id: project_id)

        target = project(scope: scope, project_id: project_id)
        return failure(Code::MissingProject, "Project memory requires an enrolled project") if scope == Scope::Project && !target

        @lock.call(key: lock_key(scope: scope, project_id: project_id)) do
          existing = @entries.for_operation(scope: scope, project_id: project_id, idempotency_key: idempotency_key)
          next Kirei::Services::Result.new(result: existing) if existing
          next failure(Code::MemoryFull, "Memory scope has reached #{MAX_ENTRIES} entries") if @entries.count(scope: scope, project_id: project_id) >= MAX_ENTRIES

          @transaction.call do
            entry = @entries.create(scope: scope, project_id: project_id, content: content.strip, source: source.strip, idempotency_key: idempotency_key)
            persist(scope: scope, project: target)
            Kirei::Services::Result.new(result: entry)
          end
        end
      rescue Platform::Lock::Busy => error
        attempts = T.must(attempts) + 1
        if attempts < LOCK_ATTEMPTS
          sleep 0.01
          retry
        end
        failure(Code::PersistenceFailed, error.message)
      rescue Adapters::Memory::Errors::WriteFailed => error
        failure(Code::PersistenceFailed, error.message)
      end

      sig { params(id: String, expected_revision: Integer, content: String, source: String, idempotency_key: String).returns(Outcome) }
      def correct(id:, expected_revision:, content:, source:, idempotency_key:)
        attempts = T.let(0, Integer)
        return invalid_content unless valid_content?(content: content, source: source, idempotency_key: idempotency_key)

        original = @entries.find(id: id)
        return failure(Code::MissingEntry, "Memory entry does not exist") unless original

        @lock.call(key: lock_key(scope: original.scope, project_id: original.project_id)) do
          existing = @entries.for_operation(scope: original.scope, project_id: original.project_id, idempotency_key: idempotency_key)
          next Kirei::Services::Result.new(result: existing) if existing

          target = project(scope: original.scope, project_id: original.project_id)
          next failure(Code::MissingProject, "Project memory requires an enrolled project") if original.scope == Scope::Project && !target

          @transaction.call do
            corrected = @entries.correct(id: id, expected_revision: expected_revision, content: content.strip, source: source.strip, idempotency_key: idempotency_key)
            next failure(Code::RevisionChanged, "Memory entry revision changed") unless corrected

            persist(scope: original.scope, project: target)
            Kirei::Services::Result.new(result: corrected)
          end
        end
      rescue Platform::Lock::Busy => error
        attempts = T.must(attempts) + 1
        if attempts < LOCK_ATTEMPTS
          sleep 0.01
          retry
        end
        failure(Code::PersistenceFailed, error.message)
      rescue Adapters::Memory::Errors::WriteFailed => error
        failure(Code::PersistenceFailed, error.message)
      end

      sig { params(scope: Scope, project_id: T.nilable(String)).returns(T.nilable(Domains::Projects::Dto::Project)) }
      private def project(scope:, project_id:)
        case scope
        when Scope::Global
          nil
        when Scope::Project
          project_id && @directory.find(id: project_id)
        else
          T.absurd(scope)
        end
      end

      sig { params(scope: Scope, project: T.nilable(Domains::Projects::Dto::Project)).void }
      private def persist(scope:, project:)
        project_id = project&.id
        @files.write(path: memory_path(scope: scope, project: project), entries: @entries.list(scope: scope, project_id: project_id, limit: MAX_ENTRIES))
      end

      sig { params(scope: Scope, project: T.nilable(Domains::Projects::Dto::Project)).returns(String) }
      private def memory_path(scope:, project:)
        case scope
        when Scope::Global then File.join(@commander_workspace, "memory.md")
        when Scope::Project then File.join(T.must(project).workspace, ".agents", "memory.md")
        else T.absurd(scope)
        end
      end

      sig { params(scope: Scope, project_id: T.nilable(String)).returns(String) }
      private def lock_key(scope:, project_id:)
        suffix = project_id || "commander"
        "memory:#{scope.serialize}:#{suffix}"
      end

      sig { params(scope: Scope, project_id: T.nilable(String)).returns(T::Boolean) }
      private def valid_scope_binding?(scope:, project_id:)
        case scope
        when Scope::Global then project_id.nil?
        when Scope::Project then !project_id.nil?
        else T.absurd(scope)
        end
      end

      sig { params(content: String, source: String, idempotency_key: String).returns(T::Boolean) }
      private def valid_content?(content:, source:, idempotency_key:)
        content.strip.bytesize.between?(1, MAX_CONTENT_BYTES) && !source.strip.empty? && !idempotency_key.strip.empty?
      end

      sig { returns(Outcome) }
      private def invalid_content = failure(Code::InvalidContent, "Memory content, source, and idempotency key are required")

      sig { params(code: Code, detail: String).returns(Outcome) }
      private def failure(code, detail)
        Kirei::Services::Result.new(errors: Platform::Failure.call(code: code, detail: detail))
      end

      sig { params(code: Code, detail: String).returns(ReadOutcome) }
      private def failure_list(code, detail)
        Kirei::Services::Result.new(errors: Platform::Failure.call(code: code, detail: detail))
      end
    end
  end
end

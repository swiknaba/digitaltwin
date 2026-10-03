# typed: strict
# frozen_string_literal: true

module Domains
  module Sessions
    # Translates stored rows into DTOs, and fails closed. T::Struct.from_hash
    # checks neither nested types nor nested unknown keys, so each JSONB value
    # is rebuilt through its constructor and compared with its stored form.
    class Records
      extend T::Sig

      sig { params(query: Sequel::Dataset).returns(T::Array[Dto::SessionView]) }
      def self.sessions(query)
        strictly { Entities::RuntimeSession.resolve(query, true).map { |entity| session(entity) } }
      end

      sig { params(query: Sequel::Dataset).returns(T::Array[Dto::OperationView]) }
      def self.operations(query)
        strictly do
          Entities::SessionOperation.resolve(query, true).map do |entity|
            Dto::OperationView.new(id: entity.id, session_id: entity.session_id, kind: entity.kind, state: entity.state, reason: entity.reason)
          end
        end
      end

      sig { params(entity: Entities::RuntimeSession).returns(Dto::SessionView) }
      private_class_method def self.session(entity)
        Dto::SessionView.new(
          id: entity.id, workflow_id: entity.workflow_id, role: entity.role, generation: entity.generation, pane_id: entity.pane_id, alias: entity.alias,
          configuration: configuration(entity.configuration), credential_digest: entity.credential_digest, credential_expires_at: entity.credential_expires_at,
          active: entity.active, last_verified_at: entity.last_verified_at, state: entity.state, runtime_identity: runtime_identity(entity.runtime_identity),
          workspace_id: entity.workspace_id, created_at: entity.created_at
        )
      end

      sig { params(stored: Workflows::Dto::RoleConfig).returns(Workflows::Dto::RoleConfig) }
      private_class_method def self.configuration(stored)
        rebuilt = Workflows::Dto::RoleConfig.new(cli: stored.cli, provider: stored.provider, model: stored.model, family: stored.family, launch_args: stored.launch_args)
        verified!(rebuilt.serialize == stored.serialize)
        rebuilt
      end

      sig { params(stored: T.nilable(Dto::RuntimeIdentity)).returns(T.nilable(Dto::RuntimeIdentity)) }
      private_class_method def self.runtime_identity(stored)
        return nil unless stored

        rebuilt = Dto::RuntimeIdentity.new(source: stored.source, agent: stored.agent, kind: stored.kind, value: stored.value)
        verified!(rebuilt.serialize == stored.serialize)
        rebuilt
      end

      sig { params(matches: T::Boolean).void }
      private_class_method def self.verified!(matches)
        raise Errors::MalformedRecord, "Malformed session record" unless matches
      end

      # from_hash raises RuntimeError for missing or unknown props and KeyError
      # for unknown enum values; constructors raise TypeError for wrong types.
      sig { type_parameters(:R).params(blk: T.proc.returns(T.type_parameter(:R))).returns(T.type_parameter(:R)) }
      private_class_method def self.strictly(&blk)
        yield
      rescue RuntimeError, KeyError, TypeError => error
        raise Errors::MalformedRecord, "Malformed session record (#{error.class})"
      end
    end
  end
end

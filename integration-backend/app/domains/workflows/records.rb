# typed: strict
# frozen_string_literal: true

module Domains
  module Workflows
    # Translates stored rows and role JSON into DTOs, and fails closed.
    # T::Struct.from_hash checks neither nested types nor nested unknown keys,
    # so each JSONB value is rebuilt through its constructor and compared with
    # its stored form. Any mismatch raises Errors::MalformedRecord.
    class Records
      extend T::Sig

      sig { params(query: Sequel::Dataset).returns(T::Array[Dto::WorkflowView]) }
      def self.workflows(query)
        strictly { Entities::Workflow.resolve(query, true).map { |entity| workflow(entity) } }
      end

      sig { params(query: Sequel::Dataset).returns(T::Array[Dto::RequestView]) }
      def self.requests(query)
        strictly { Entities::WorkflowRequest.resolve(query, true).map { |entity| request(entity) } }
      end

      sig { params(query: Sequel::Dataset).returns(T::Array[Dto::ApprovalView]) }
      def self.approvals(query)
        strictly { Entities::Approval.resolve(query, true).map { |entity| approval(entity) } }
      end

      sig { params(query: Sequel::Dataset).returns(T::Array[Dto::QueuedMessageView]) }
      def self.queued_messages(query)
        strictly do
          Entities::QueuedMessage.resolve(query, true).map do |entity|
            Dto::QueuedMessageView.new(id: entity.id, workflow_id: entity.workflow_id, inbox_id: entity.inbox_id, workflow_version: entity.workflow_version)
          end
        end
      end

      # Parses ROLE_CONFIG_FILE content with the same strict rules as stored rows.
      sig { params(json: String).returns(Dto::RoleFile) }
      def self.role_file_from_json(json)
        strictly { role_file(Dto::RoleFile.from_hash(JSON.parse(json), true)) }
      rescue JSON::ParserError
        raise Errors::MalformedRecord, "Malformed role configuration"
      end

      sig { params(entity: Entities::Workflow).returns(Dto::WorkflowView) }
      private_class_method def self.workflow(entity)
        Dto::WorkflowView.new(
          id: entity.id, project_id: entity.project_id, channel_id: entity.channel_id, thread_id: entity.thread_id, branch: entity.branch,
          worktree_path: entity.worktree_path, phase: entity.phase, saved_phase: entity.saved_phase, version: entity.version,
          artifacts: artifact_set(entity.artifacts), blocker: entity.blocker, archived_at: entity.archived_at, created_at: entity.created_at,
          paused_commit: entity.paused_commit, source_inbox_id: entity.source_inbox_id, role_configurations: role_assignments(entity.role_configurations)
        )
      end

      sig { params(entity: Entities::WorkflowRequest).returns(Dto::RequestView) }
      private_class_method def self.request(entity)
        stored = entity.parameters
        parameters = Dto::RequestParameters.new(title: stored.title, existing_thread: stored.existing_thread, roles: role_assignments(stored.roles))
        verified!(parameters.serialize == stored.serialize)
        Dto::RequestView.new(
          id: entity.id, inbox_id: entity.inbox_id, project_id: entity.project_id, workflow_id: entity.workflow_id, request_digest: entity.request_digest,
          parameters: parameters, state: entity.state, thread_id: entity.thread_id, reason: entity.reason, created_at: entity.created_at
        )
      end

      sig { params(entity: Entities::Approval).returns(Dto::ApprovalView) }
      private_class_method def self.approval(entity)
        Dto::ApprovalView.new(id: entity.id, workflow_id: entity.workflow_id, gate: entity.kind, target_commit: entity.target_commit,
                              user_id: entity.user_id, channel_id: entity.channel_id, post_id: entity.post_id, created_at: entity.created_at)
      end

      sig { params(stored: Dto::ArtifactSet).returns(Dto::ArtifactSet) }
      private_class_method def self.artifact_set(stored)
        artifacts = Dto::ArtifactSet.new(plan: artifact_ref(stored.plan), spec: artifact_ref(stored.spec), implementation: artifact_ref(stored.implementation))
        verified!(artifacts.serialize == stored.serialize)
        artifacts
      end

      sig { params(stored: T.nilable(Dto::ArtifactRef)).returns(T.nilable(Dto::ArtifactRef)) }
      private_class_method def self.artifact_ref(stored)
        stored && Dto::ArtifactRef.new(commit: stored.commit, path: stored.path)
      end

      sig { params(stored: Dto::RoleAssignments).returns(Dto::RoleAssignments) }
      private_class_method def self.role_assignments(stored)
        controller = stored.controller
        roles = Dto::RoleAssignments.new(writer: role_config(stored.writer), reviewer: role_config(stored.reviewer),
                                         controller: controller && role_config(controller))
        verified!(roles.serialize == stored.serialize)
        roles
      end

      sig { params(stored: Dto::RoleFile).returns(Dto::RoleFile) }
      private_class_method def self.role_file(stored)
        writer = stored.writer
        reviewer = stored.reviewer
        controller = stored.controller
        file = Dto::RoleFile.new(writer: writer && role_config(writer), reviewer: reviewer && role_config(reviewer),
                                 controller: controller && role_config(controller))
        verified!(file.serialize == stored.serialize)
        file
      end

      sig { params(stored: Dto::RoleConfig).returns(Dto::RoleConfig) }
      private_class_method def self.role_config(stored)
        Dto::RoleConfig.new(cli: stored.cli, provider: stored.provider, model: stored.model, family: stored.family, launch_args: stored.launch_args)
      end

      sig { params(matches: T::Boolean).void }
      private_class_method def self.verified!(matches)
        raise Errors::MalformedRecord, "Malformed workflow record" unless matches
      end

      # from_hash raises RuntimeError for missing or unknown props and KeyError
      # for unknown enum values; constructors raise TypeError for wrong types.
      sig { type_parameters(:R).params(blk: T.proc.returns(T.type_parameter(:R))).returns(T.type_parameter(:R)) }
      private_class_method def self.strictly(&blk)
        yield
      rescue RuntimeError, KeyError, TypeError => error
        raise Errors::MalformedRecord, "Malformed workflow record (#{error.class})"
      end
    end
  end
end

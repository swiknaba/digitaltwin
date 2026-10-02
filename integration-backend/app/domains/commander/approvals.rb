# typed: strict
# frozen_string_literal: true

module Domains
  module Commander
    class Approvals
      extend T::Sig

      Gate = T.type_alias { String }
      CurrentCommitSource = T.type_alias { T.proc.params(worktree: Adapters::Git::Dto::WorktreeRef).returns(String) }

      sig do
        params(
          db: Sequel::Database,
          resolver: Domains::Messaging::DeliveryVerifier,
          membership: T.proc.params(channel_id: String, user_id: String).returns(T::Boolean),
          current_commit: CurrentCommitSource,
          handle: String,
          evidence: T.nilable(Adapters::Git::Evidence)
        ).void
      end
      def initialize(db, resolver:, membership:, current_commit:, handle: ENV.fetch("AGENT_HANDLE", "agent"), evidence: nil)
        @db = db
        @resolver = resolver
        @membership = membership
        @current_commit = current_commit
        @handle = handle
        @evidence = evidence
      end

      sig { params(inbox_id: String, workflow_id: String, gate: Gate, commit: String).returns(String) }
      def record(inbox_id:, workflow_id:, gate:, commit:)
        raise ArgumentError, "Exact approval required" unless %w[spec plan].include?(gate) && commit.match?(/\A[0-9a-f]{40}\z/)

        source = Domains::Messaging::Inbox.new.find(id: inbox_id) or raise ArgumentError, "Missing source"
        d = @resolver.delivery(post_id: source.post_id, channel_id: source.channel_id, event_kind: Domains::Messaging::Dto::EventKind::Posted)
        raise ArgumentError, "Human source changed" unless d.actor.member && !d.actor.bot && d.actor.user_id == source.user_id && d.post_revision == source.post_revision

        catalog = Domains::Workflows::Catalog.new
        w = catalog.find(id: workflow_id) or raise ArgumentError, "Missing workflow"
        contextual = d.channel_id == w.channel_id && d.thread_id == w.thread_id && d.body == "@#{ENV.fetch("WORKER_HANDLE", "worker")} approve"
        exact = d.body == "@#{@handle} approve #{workflow_id} #{gate} #{commit}"
        raise ArgumentError, "Approval requires exact or verified thread binding" unless exact || contextual
        raise ArgumentError, "Destination membership required" unless @membership.call(w.channel_id, d.actor.user_id)

        # Platform::Lock::Busy is the ArgumentError "Workflow busy" this path raised before.
        Platform::Lock.new.call(key: workflow_id) do
          current = @current_commit.call(worktree(w))
          @db.transaction do
            locked = catalog.find_for_update(id: workflow_id) or raise ArgumentError, "Missing workflow"
            review = @db[:reviews].where(workflow_id: workflow_id, gate: gate).order(Sequel.desc(:round)).first
            review_commit = optional_text(review && review[:review_commit])
            approved = review && review[:verdict] == "approve" && review[:target_commit] == commit && current == (review_commit || commit)
            raise ArgumentError, "Approval binding is stale" unless !locked.archived_at && locked.phase.serialize == "#{gate}_human_approval" && approved

            gate_value = Domains::Workflows::Dto::Gate.deserialize(gate)
            @evidence&.approval(worktree: worktree(locked), binding: locked.artifacts.fetch(gate_value), target_commit: commit,
                                review_commit: review_commit, review_path: optional_text(review[:review_path]))
            Platform::Unwrap.call(Domains::Workflows::Approvals.new.record(workflow_id: workflow_id, gate: gate_value, target_commit: commit, user_id: d.actor.user_id,
                                                                           channel_id: d.channel_id, post_id: d.post_id)).id
          end
        end
      end

      sig { params(workflow: Domains::Workflows::Dto::WorkflowView).returns(Adapters::Git::Dto::WorktreeRef) }
      private def worktree(workflow)
        Adapters::Git::Dto::WorktreeRef.new(worktree_path: workflow.worktree_path, branch: workflow.branch)
      end

      # Raw review values are untyped until Task 8; BasicObject accepts them without a cast.
      sig { params(value: BasicObject).returns(T.nilable(String)) }
      private def optional_text(value)
        case value
        when NilClass, String then value
        else raise ArgumentError, "Malformed durable review record"
        end
      end
    end
  end
end

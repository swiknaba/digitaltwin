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
          resolver: Source::DeliveryResolver,
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

      sig { params(inbox_id: T.any(Integer, String), workflow_id: String, gate: Gate, commit: String).returns(Integer) }
      def record(inbox_id:, workflow_id:, gate:, commit:)
        raise ArgumentError, "Exact approval required" unless %w[spec plan].include?(gate) && commit.match?(/\A[0-9a-f]{40}\z/)

        source = @db[:inbox][id: inbox_id] or raise ArgumentError, "Missing source"
        d = @resolver.delivery(post_id: source[:post_id], channel_id: source[:channel_id], event_kind: "posted")
        raise ArgumentError, "Human source changed" unless d.actor.member && !d.actor.bot && d.actor.user_id == source[:user_id] && d.post_revision == source[:post_revision]

        w = @db[:workflows][id: workflow_id] or raise ArgumentError, "Missing workflow"
        contextual = d.channel_id == w[:channel_id] && d.thread_id == w[:thread_id] && d.body == "@#{ENV.fetch("WORKER_HANDLE", "worker")} approve"
        exact = d.body == "@#{@handle} approve #{workflow_id} #{gate} #{commit}"
        raise ArgumentError, "Approval requires exact or verified thread binding" unless exact || contextual
        raise ArgumentError, "Destination membership required" unless @membership.call(w[:channel_id], d.actor.user_id)

        @db.synchronize do
          locked = @db.get(Sequel.function(:pg_try_advisory_lock, Sequel.function(:hashtextextended, workflow_id, 0)))
          raise ArgumentError, "Workflow busy" unless locked

          begin
            current = @current_commit.call(worktree(w[:worktree_path], w[:branch]))
            @db.transaction do
              w = @db[:workflows].where(id: workflow_id).for_update.first
              review = @db[:reviews].where(workflow_id: workflow_id, gate: gate).order(Sequel.desc(:round)).first
              raise ArgumentError, "Approval binding is stale" unless !w[:archived_at] && w[:phase] == "#{gate}_human_approval" && review && review[:verdict] == "approve" && review[:target_commit] == commit && current == (review[:review_commit] || commit)

              @evidence&.approval(worktree: worktree(w[:worktree_path], w[:branch]), binding: artifact_binding(w[:artifacts], gate), target_commit: commit,
                                  review_commit: review[:review_commit], review_path: review[:review_path])

              old = @db[:approvals][post_id: d.post_id]
              if old
                raise ArgumentError, "Source approval already bound" unless old[:workflow_id] == workflow_id && old[:kind] == gate && old[:target_commit] == commit

                return old[:id]
              end
              @db[:approvals].insert_conflict(target: %i[workflow_id kind target_commit]).insert(
                workflow_id: workflow_id, kind: gate, target_commit: commit, user_id: d.actor.user_id,
                channel_id: d.channel_id, post_id: d.post_id
              )
            end
          ensure
            @db.get(Sequel.function(:pg_advisory_unlock, Sequel.function(:hashtextextended, workflow_id, 0)))
          end
        end
      end

      sig { params(worktree_path: Object, branch: Object).returns(Adapters::Git::Dto::WorktreeRef) }
      private def worktree(worktree_path, branch)
        raise ArgumentError, "Invalid workflow evidence" unless worktree_path.is_a?(String) && branch.is_a?(String)

        Adapters::Git::Dto::WorktreeRef.new(worktree_path: worktree_path, branch: branch)
      end

      sig { params(artifacts: BasicObject, gate: String).returns(T.nilable(Adapters::Git::Dto::ArtifactBinding)) }
      private def artifact_binding(artifacts, gate)
        # Sequel returns JSONB columns as a Delegator, which is not an Object.
        refs = Sequel::Postgres::JSONBHash === artifacts ? artifacts.to_hash : Hash.try_convert(artifacts)
        ref = refs && Hash.try_convert(refs[gate])
        return nil unless ref

        commit = ref["commit"]
        path = ref["path"]
        Adapters::Git::Dto::ArtifactBinding.new(commit: commit.is_a?(String) ? commit : nil, path: path.is_a?(String) ? path : nil)
      end
    end
  end
end

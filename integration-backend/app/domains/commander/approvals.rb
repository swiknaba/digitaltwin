# typed: strict
# frozen_string_literal: true

module Domains
  module Commander
    class Approvals
      extend T::Sig

      module CurrentCommit
        extend T::Helpers
        extend T::Sig

        interface!

        sig { abstract.params(workflow: GitRevision::Workflow).returns(String) }
        def call(workflow); end
      end

      Gate = T.type_alias { String }
      CurrentCommitSource = T.type_alias do
        T.any(CurrentCommit, T.proc.params(workflow: GitRevision::Workflow).returns(String))
      end

      sig do
        params(
          db: Sequel::Database,
          resolver: Source::DeliveryResolver,
          membership: T.proc.params(channel_id: String, user_id: String).returns(T::Boolean),
          current_commit: CurrentCommitSource,
          handle: String,
          evidence: T.nilable(Domains::Reviews::GitEvidence)
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
            current = current_commit(w)
            @db.transaction do
              w = @db[:workflows].where(id: workflow_id).for_update.first
              review = @db[:reviews].where(workflow_id: workflow_id, gate: gate).order(Sequel.desc(:round)).first
              raise ArgumentError, "Approval binding is stale" unless !w[:archived_at] && w[:phase] == "#{gate}_human_approval" && review && review[:verdict] == "approve" && review[:target_commit] == commit && current == (review[:review_commit] || commit)

              @evidence.approval(w, review) if @evidence

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

      private

      # Tests and embedding callers have historically provided a callable
      # revision verifier. Keep that narrow seam while production uses the
      # explicit CurrentCommit interface implemented by GitRevision.
      sig { params(workflow: GitRevision::Workflow).returns(String) }
      def current_commit(workflow)
        @current_commit.call(workflow)
      end
    end
  end
end

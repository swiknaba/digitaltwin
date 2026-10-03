# typed: strict
# frozen_string_literal: true

module Adapters
  module Git
    # Git evidence for review and approval gates: exact revisions, append-only
    # review files, and unchanged approved artifacts. Failures raise ArgumentError.
    class Evidence
      extend T::Sig

      sig { params(revision: Revision).void }
      def initialize(revision:)
        @revision = revision
      end

      sig { params(worktree: Dto::WorktreeRef).returns(String) }
      def current(worktree:) = clean_revision(worktree)

      sig { params(worktree: Dto::WorktreeRef).returns(String) }
      def head(worktree:) = git(worktree, "rev-parse", "HEAD")

      sig { params(worktree: Dto::WorktreeRef, commit: String, path: T.nilable(String)).returns(TrueClass) }
      def artifact(worktree:, commit:, path:)
        raise ArgumentError, "Revision moved" unless clean_revision(worktree) == commit

        path!(path)
        git(worktree, "cat-file", "-e", "#{commit}:#{path}") if path
        true
      end

      sig { params(worktree: Dto::WorktreeRef, commit: String).returns(String) }
      def base(worktree:, commit:) = git(worktree, "merge-base", "origin/HEAD", commit)

      sig do
        params(worktree: Dto::WorktreeRef, target_commit: String, review_path: String, review_commit: String, verdict: String,
               reviewer: Dto::ReviewerIdentity).returns(TrueClass)
      end
      def review(worktree:, target_commit:, review_path:, review_commit:, verdict:, reviewer:)
        raise ArgumentError, "Review commit moved" unless clean_revision(worktree) == review_commit

        path!(review_path)
        files = git(worktree, "diff", "--name-only", target_commit, review_commit).lines.map(&:strip)
        raise ArgumentError, "Reviewer modified another file" unless files == [review_path]

        content = git(worktree, "show", "#{review_commit}:#{review_path}")
        previous = git(worktree, "show", "#{target_commit}:#{review_path}", missing: true)
        raise ArgumentError, "Review history was rewritten" unless content.start_with?(previous)

        appended = content.delete_prefix(previous)
        fields = { "Target" => target_commit, "Provider" => reviewer.provider, "Model" => reviewer.model, "Family" => reviewer.family, "Verdict" => verdict }
        raise ArgumentError, "Review metadata missing" unless fields.all? { |key, value| appended.lines.any? { |line| line.strip == "#{key}: #{value}" } }
        raise ArgumentError, "Review timestamp missing" unless appended.match?(/^Reviewed-at: \d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/)

        true
      end

      sig { params(worktree: Dto::WorktreeRef, binding: T.nilable(Domains::Workflows::Dto::ArtifactRef), target_commit: String).returns(TrueClass) }
      def approved_artifact(worktree:, binding:, target_commit:)
        current = clean_revision(worktree)
        path = binding&.path
        raise ArgumentError, "Approval artifact binding changed" unless binding&.commit == target_commit && path

        path!(path)
        expected = git(worktree, "rev-parse", "#{target_commit}:#{path}")
        actual = git(worktree, "rev-parse", "#{current}:#{path}")
        raise ArgumentError, "Previously approved artifact changed" unless expected == actual

        true
      end

      sig do
        params(worktree: Dto::WorktreeRef, binding: T.nilable(Domains::Workflows::Dto::ArtifactRef), target_commit: String,
               review_commit: T.nilable(String), review_path: T.nilable(String)).returns(TrueClass)
      end
      def approval(worktree:, binding:, target_commit:, review_commit:, review_path:)
        current = clean_revision(worktree)
        raise ArgumentError, "Approval revision moved" unless current == (review_commit || target_commit)

        path = binding&.path
        raise ArgumentError, "Artifact binding missing" unless binding&.commit == target_commit && path

        path!(path)
        git(worktree, "cat-file", "-e", "#{target_commit}:#{path}")
        if review_commit
          raise ArgumentError, "Invalid review evidence" unless review_path

          files = git(worktree, "diff", "--name-only", target_commit, current).lines.map(&:strip)
          raise ArgumentError, "Reviewed artifact changed" unless files == [review_path]
        end
        true
      end

      sig { params(worktree: Dto::WorktreeRef).returns(String) }
      private def clean_revision(worktree)
        @revision.call(worktree_path: worktree.worktree_path, branch: worktree.branch)
      end

      sig { params(path: T.nilable(String)).void }
      private def path!(path)
        raise ArgumentError, "Invalid artifact path" if path && (!path.match?(/\A[a-zA-Z0-9_.\/-]+\.md\z/) || path.split("/").any? { |part| %w[. ..].include?(part) } || path.start_with?("/"))
      end

      sig do
        params(worktree: Dto::WorktreeRef, command: String, argument: String, subject: T.nilable(String), revision: T.nilable(String),
               missing: T::Boolean).returns(String)
      end
      private def git(worktree, command, argument, subject = nil, revision = nil, missing: false)
        path = worktree.worktree_path
        output, status = if revision && subject
                           Open3.capture2e("git", "-C", path, command, argument, subject, revision)
                         elsif subject
                           Open3.capture2e("git", "-C", path, command, argument, subject)
                         else
                           Open3.capture2e("git", "-C", path, command, argument)
                         end
        return "" if missing && !status.success?
        raise ArgumentError, "Git evidence unavailable" unless status.success?

        command == "show" ? output : output.delete_suffix("\n")
      end
    end
  end
end

# typed: strict
# frozen_string_literal: true


module Domains
  module Reviews
    class GitEvidence
      extend T::Sig

      ArtifactRef = T.type_alias { T::Hash[String, T.nilable(String)] }
      ArtifactRefs = T.type_alias { T::Hash[String, ArtifactRef] }
      Workflow = T.type_alias { T::Hash[Symbol, T.any(String, ArtifactRefs)] }
      ReviewRecord = T.type_alias { T::Hash[Symbol, T.nilable(String)] }
      Approval = T.type_alias { T::Hash[Symbol, String] }
      Configuration = T.type_alias { T::Hash[String, String] }

      sig { params(revision: Domains::Commander::GitRevision).void }
      def initialize(revision: Domains::Commander::GitRevision.new)
        @revision = revision
      end

      sig { params(workflow: Workflow).returns(String) }
      def current(workflow) = @revision.call(workflow)

      sig { params(workflow: Workflow).returns(String) }
      def head(workflow) = git(workflow, "rev-parse", "HEAD")

      sig { params(workflow: Workflow, commit: String, path: T.nilable(String)).returns(TrueClass) }
      def artifact(workflow, commit, path)
        raise ArgumentError, "Revision moved" unless @revision.call(workflow) == commit

        path!(path)
        git(workflow, "cat-file", "-e", "#{commit}:#{path}") if path
        true
      end

      sig { params(workflow: Workflow, commit: String).returns(String) }
      def base(workflow, commit) = git(workflow, "merge-base", "origin/HEAD", commit)

      sig do
        params(workflow: Workflow, record: ReviewRecord, commit: String, verdict: String,
               configuration: Configuration).returns(TrueClass)
      end
      def review(workflow, record, commit, verdict, configuration)
        raise ArgumentError, "Review commit moved" unless @revision.call(workflow) == commit

        path = required_record_value(record, :review_path)
        path!(path)
        target_commit = required_record_value(record, :target_commit)
        files = git(workflow, "diff", "--name-only", target_commit, commit).lines.map(&:strip)
        raise ArgumentError, "Reviewer modified another file" unless files == [path]

        content = git(workflow, "show", "#{commit}:#{path}")
        previous = git(workflow, "show", "#{target_commit}:#{path}", missing: true)
        raise ArgumentError, "Review history was rewritten" unless content.start_with?(previous)

        appended = content.delete_prefix(previous)
        fields = { "Target" => target_commit, "Provider" => configuration.fetch("provider"), "Model" => configuration.fetch("model"), "Family" => configuration.fetch("family"), "Verdict" => verdict }
        raise ArgumentError, "Review metadata missing" unless fields.all? { |key, value| appended.lines.any? { |line| line.strip == "#{key}: #{value}" } }
        raise ArgumentError, "Review timestamp missing" unless appended.match?(/^Reviewed-at: \d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/)

        true
      end

      sig { params(workflow: Workflow, approval: Approval).returns(TrueClass) }
      def approved_artifact(workflow, approval)
        current = @revision.call(workflow)
        ref = artifact_ref(workflow, approval.fetch(:kind))
        target_commit = approval.fetch(:target_commit)
        raise ArgumentError, "Approval artifact binding changed" unless ref && ref.fetch("commit") == target_commit && ref.fetch("path")

        path = ref.fetch("path")
        path!(path)
        expected = git(workflow, "rev-parse", "#{target_commit}:#{path}")
        actual = git(workflow, "rev-parse", "#{current}:#{ref["path"]}")
        raise ArgumentError, "Previously approved artifact changed" unless expected == actual

        true
      end

      sig { params(workflow: Workflow, record: ReviewRecord).returns(TrueClass) }
      def approval(workflow, record)
        current = @revision.call(workflow)
        target_commit = required_record_value(record, :target_commit)
        review_commit = record.fetch(:review_commit)
        raise ArgumentError, "Approval revision moved" unless current == (review_commit || target_commit)

        ref = artifact_ref(workflow, required_record_value(record, :gate))
        raise ArgumentError, "Artifact binding missing" unless ref && ref.fetch("commit") == target_commit && ref.fetch("path")

        path = ref.fetch("path")
        path!(path)
        git(workflow, "cat-file", "-e", "#{target_commit}:#{path}")
        if review_commit
          files = git(workflow, "diff", "--name-only", target_commit, current).lines.map(&:strip)
          raise ArgumentError, "Reviewed artifact changed" unless files == [required_record_value(record, :review_path)]
        end
        true
      end

      private

      sig { params(path: T.nilable(String)).void }
      def path!(path)
        raise ArgumentError, "Invalid artifact path" if path && (!path.match?(/\A[a-zA-Z0-9_.\/-]+\.md\z/) || path.split("/").any? { |part| %w[. ..].include?(part) } || path.start_with?("/"))
      end

      sig do
        params(workflow: Workflow, command: String, argument: String, subject: T.nilable(String), revision: T.nilable(String),
               missing: T::Boolean).returns(String)
      end
      def git(workflow, command, argument, subject = nil, revision = nil, missing: false)
        worktree_path = required_workflow_value(workflow, :worktree_path)
        output, status = if revision && subject
                           Open3.capture2e("git", "-C", worktree_path, command, argument, subject, revision)
                         elsif subject
                           Open3.capture2e("git", "-C", worktree_path, command, argument, subject)
                         else
                           Open3.capture2e("git", "-C", worktree_path, command, argument)
                         end
        return "" if missing && !status.success?
        raise ArgumentError, "Git evidence unavailable" unless status.success?

        command == "show" ? output : output.delete_suffix("\n")
      end

      sig { params(workflow: Workflow, key: Symbol).returns(String) }
      def required_workflow_value(workflow, key)
        value = workflow.fetch(key)
        raise ArgumentError, "Invalid workflow evidence" unless value.is_a?(String)

        value
      end

      sig { params(workflow: Workflow, kind: String).returns(T.nilable(ArtifactRef)) }
      def artifact_ref(workflow, kind)
        artifacts = workflow.fetch(:artifacts)
        raise ArgumentError, "Invalid workflow artifacts" unless artifacts.is_a?(Hash)

        artifacts[kind]
      end

      sig { params(record: ReviewRecord, key: Symbol).returns(String) }
      def required_record_value(record, key)
        value = record.fetch(key)
        raise ArgumentError, "Invalid review evidence" unless value.is_a?(String)

        value
      end
    end
  end
end

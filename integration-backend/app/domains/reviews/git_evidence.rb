# frozen_string_literal: true

module Domains
  module Reviews
    class GitEvidence
      def initialize(revision: Domains::Controller::GitRevision.new) = @revision = revision
      def current(workflow) = @revision.call(workflow)
      def head(workflow) = git(workflow, "rev-parse", "HEAD")

      def artifact(workflow, commit, path)
        raise ArgumentError, "Revision moved" unless @revision.call(workflow) == commit

        path!(path)
        git(workflow, "cat-file", "-e", "#{commit}:#{path}") if path
        true
      end

      def base(workflow, commit) = git(workflow, "merge-base", "origin/HEAD", commit)

      def review(workflow, record, commit, verdict, configuration)
        raise ArgumentError, "Review commit moved" unless @revision.call(workflow) == commit

        path = record[:review_path]
        path!(path)
        files = git(workflow, "diff", "--name-only", record[:target_commit], commit).lines.map(&:strip)
        raise ArgumentError, "Reviewer modified another file" unless files == [path]

        content = git(workflow, "show", "#{commit}:#{path}")
        previous = git(workflow, "show", "#{record[:target_commit]}:#{path}", missing: true)
        raise ArgumentError, "Review history was rewritten" unless content.start_with?(previous)

        appended = content.delete_prefix(previous)
        fields = { "Target" => record[:target_commit], "Provider" => configuration.fetch("provider"), "Model" => configuration.fetch("model"), "Family" => configuration.fetch("family"), "Verdict" => verdict }
        raise ArgumentError, "Review metadata missing" unless fields.all? { |key, value| appended.lines.any? { |line| line.strip == "#{key}: #{value}" } }
        raise ArgumentError, "Review timestamp missing" unless appended.match?(/^Reviewed-at: \d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/)

        true
      end

      def approved_artifact(workflow, approval)
        current = @revision.call(workflow)
        ref = workflow[:artifacts][approval[:kind]]
        raise ArgumentError, "Approval artifact binding changed" unless ref && ref["commit"] == approval[:target_commit] && ref["path"]

        path!(ref["path"])
        expected = git(workflow, "rev-parse", "#{approval[:target_commit]}:#{ref['path']}")
        actual = git(workflow, "rev-parse", "#{current}:#{ref['path']}")
        raise ArgumentError, "Previously approved artifact changed" unless expected == actual

        true
      end

      def approval(workflow, record)
        current = @revision.call(workflow)
        raise ArgumentError, "Approval revision moved" unless current == (record[:review_commit] || record[:target_commit])

        ref = workflow[:artifacts][record[:gate]]
        raise ArgumentError, "Artifact binding missing" unless ref && ref["commit"] == record[:target_commit] && ref["path"]

        path!(ref["path"])
        git(workflow, "cat-file", "-e", "#{record[:target_commit]}:#{ref['path']}")
        if record[:review_commit]
          files = git(workflow, "diff", "--name-only", record[:target_commit], current).lines.map(&:strip)
          raise ArgumentError, "Reviewed artifact changed" unless files == [record[:review_path]]
        end
        true
      end
      private def path!(path)
        raise ArgumentError, "Invalid artifact path" if path && (!path.match?(/\A[a-zA-Z0-9_.\/-]+\.md\z/) || path.split("/").any? { |part| %w[. ..].include?(part) } || path.start_with?("/"))
      end
      private def git(workflow, *args, missing: false)
        output, status = Open3.capture2e("git", "-C", workflow[:worktree_path], *args)
        return "" if missing && !status.success?
        raise ArgumentError, "Git evidence unavailable" unless status.success?

        args.first == "show" ? output : output.delete_suffix("\n")
      end
    end
  end
end

# typed: strict
# frozen_string_literal: true

require "open3"

module Domains
  module Controller
    class GitRevision
      extend T::Sig
      include Approvals::CurrentCommit

      Workflow = T.type_alias { T::Hash[Symbol, Object] }

      sig { params(root: String).void }
      def initialize(root: ENV.fetch("WORKTREE_ROOT", "/workspace/worktrees"))
        @root = root
      end

      sig { override.params(workflow: Workflow).returns(String) }
      def call(workflow)
        root = File.realpath(@root)
        path = File.realpath(workflow_value(workflow, :worktree_path))
        raise ArgumentError, "Worktree outside configured root" unless path.start_with?("#{root}/")

        output, status = Open3.capture2e("git", "-C", path, "branch", "--show-current")
        raise ArgumentError, "Worktree branch mismatch" unless status.success? && output.strip == workflow_value(workflow, :branch)

        output, status = Open3.capture2e("git", "-C", path, "status", "--porcelain")
        raise ArgumentError, "Worktree has uncommitted changes" unless status.success? && output.empty?

        output, status = Open3.capture2e("git", "-C", path, "rev-parse", "HEAD")
        revision = output.strip
        raise ArgumentError, "Invalid Git revision" unless status.success? && revision.match?(/\A[0-9a-f]{40}\z/)

        revision
      rescue Errno::ENOENT, Errno::ENOTDIR
        raise ArgumentError, "Invalid worktree path"
      end

      private

      sig { params(workflow: Workflow, key: Symbol).returns(String) }
      def workflow_value(workflow, key)
        value = workflow.fetch(key)
        raise ArgumentError, "Invalid workflow evidence" unless value.is_a?(String)

        value
      end
    end
  end
end

# frozen_string_literal: true

require "open3"
module Domains
  module Controller
    class GitRevision
      def initialize(root: ENV.fetch("WORKTREE_ROOT", "/workspace/worktrees")) = @root = root

      def call(workflow)
        root = File.realpath(@root)
        path = File.realpath(workflow[:worktree_path])
        raise ArgumentError, "Worktree outside configured root" unless path.start_with?("#{root}/")

        output, status = Open3.capture2e("git", "-C", path, "branch", "--show-current")
        raise ArgumentError, "Worktree branch mismatch" unless status.success? && output.strip == workflow[:branch]

        output, status = Open3.capture2e("git", "-C", path, "status", "--porcelain")
        raise ArgumentError, "Worktree has uncommitted changes" unless status.success? && output.empty?

        output, status = Open3.capture2e("git", "-C", path, "rev-parse", "HEAD")
        raise ArgumentError, "Invalid Git revision" unless status.success? && output.strip.match?(/\A[0-9a-f]{40}\z/)

        output.strip
      end
    end
  end
end

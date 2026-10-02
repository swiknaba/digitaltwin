# typed: strict
# frozen_string_literal: true

module Adapters
  module Git
    # Reads the exact clean revision of a bound worktree under the configured root.
    class Revision
      extend T::Sig

      sig { params(root: String).void }
      def initialize(root:)
        @root = root
      end

      sig { params(worktree_path: String, branch: String).returns(String) }
      def call(worktree_path:, branch:)
        root = File.realpath(@root)
        path = File.realpath(worktree_path)
        raise ArgumentError, "Worktree outside configured root" unless path.start_with?("#{root}/")

        output, status = Open3.capture2e("git", "-C", path, "branch", "--show-current")
        raise ArgumentError, "Worktree branch mismatch" unless status.success? && output.strip == branch

        output, status = Open3.capture2e("git", "-C", path, "status", "--porcelain")
        raise ArgumentError, "Worktree has uncommitted changes" unless status.success? && output.empty?

        output, status = Open3.capture2e("git", "-C", path, "rev-parse", "HEAD")
        revision = output.strip
        raise ArgumentError, "Invalid Git revision" unless status.success? && revision.match?(/\A[0-9a-f]{40}\z/)

        revision
      rescue Errno::ENOENT, Errno::ENOTDIR
        raise ArgumentError, "Invalid worktree path"
      end
    end
  end
end

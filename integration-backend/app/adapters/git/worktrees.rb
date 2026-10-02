# typed: strict
# frozen_string_literal: true

module Adapters
  module Git
    # Local git queries and worktree creation for repository workspaces.
    class Worktrees
      extend T::Sig

      sig { params(repo: String).returns(String) }
      def top_level(repo:)
        checked_output(*Open3.capture2e("git", "-C", repo, "rev-parse", "--show-toplevel"))
      end

      sig { params(repo: String).returns(String) }
      def remote(repo:)
        checked_output(*Open3.capture2e("git", "-C", repo, "remote", "get-url", "origin"))
      end

      sig { params(repo: String, branch: String, path: String).void }
      def add(repo:, branch:, path:)
        checked_output(*Open3.capture2e("git", "-C", repo, "worktree", "add", "-b", branch, path, "HEAD"))
      end

      sig { params(repo: String).returns(String) }
      def branch(repo:)
        checked_output(*Open3.capture2e("git", "-C", repo, "branch", "--show-current"))
      end

      sig { params(repo: String).returns(String) }
      def common_dir(repo:)
        checked_output(*Open3.capture2e("git", "-C", repo, "rev-parse", "--path-format=absolute", "--git-common-dir"))
      end

      private

      sig { params(output: String, status: Process::Status).returns(String) }
      def checked_output(output, status)
        raise Errors::ValidationFailed, "Git validation failed" unless status.success?

        output.strip
      end
    end
  end
end

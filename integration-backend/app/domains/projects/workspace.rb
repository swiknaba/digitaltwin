# typed: strict
# frozen_string_literal: true

require "fileutils"
require "open3"
module Domains
  module Projects
    class Workspace
      extend T::Sig

      UUID_PATTERN = T.let(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/, Regexp)

      sig { params(root: String, worktrees_root: String).void }
      def initialize(root: ENV.fetch("WORKSPACE_ROOT", "/workspace/repos"),
                     worktrees_root: ENV.fetch("WORKTREE_ROOT", "/workspace/worktrees"))
        @root = T.let(File.realpath(root), String)
        @trees = T.let(File.realpath(worktrees_root), String)
      end

      sig { params(slug: String).returns(String) }
      def resolve(slug:)
        RepositoryIdentity.slug!(slug)
        path = contained!(@root, File.join(@root, slug))
        raise ArgumentError, "Repository missing: choose clone/create_private/stop" unless File.directory?(path)
        raise ArgumentError, "Expected repository root" unless File.realpath(git_top_level(path)) == path

        RepositoryIdentity.remote!(git_remote(path), slug)
        path
      end

      sig { params(slug: String).returns(String) }
      def destination(slug:)
        RepositoryIdentity.slug!(slug)
        contained!(@root, File.join(@root, slug))
      end

      sig { params(slug: String, workflow_id: String, branch: String).returns(String) }
      def for_workflow(slug:, workflow_id:, branch:)
        raise ArgumentError,
              "Invalid workflow UUID/branch" unless workflow_id.match?(UUID_PATTERN) && branch == "digitaltwin/#{workflow_id}"

        path = contained!(@trees, File.join(@trees, workflow_id))
        repo = resolve(slug: slug)
        git_worktree_add(repo, branch, path) unless File.exist?(path)
        raise ArgumentError, "Worktree branch mismatch" unless git_branch(path) == branch

        common = git_common_dir(path)
        expected = git_common_dir(repo)
        raise ArgumentError, "Worktree repository mismatch" unless File.realpath(common) == File.realpath(expected)
        raise ArgumentError, "Worktree root mismatch" unless File.realpath(git_top_level(path)) == path

        RepositoryIdentity.remote!(git_remote(path), slug)
        path
      end

      private

      sig { params(root: String, path: String).returns(String) }
      def contained!(root, path)
        expanded = File.expand_path(path)
        raise ArgumentError, "Workspace escape" unless expanded.start_with?("#{root}/")

        ancestor = expanded
        loop do
          if File.symlink?(ancestor)
            raise ArgumentError, "Workspace symlinks are not accepted"
          elsif File.exist?(ancestor)
            real = File.realpath(ancestor)
            raise ArgumentError, "Workspace escape" unless real == root || real.start_with?("#{root}/")
          end
          break if ancestor == root

          ancestor = File.dirname(ancestor)
        end
        expanded
      end
      sig { params(repo: String).returns(String) }
      def git_top_level(repo)
        output, status = Open3.capture2e("git", "-C", repo, "rev-parse", "--show-toplevel")
        checked_output(output, status)
      end

      sig { params(repo: String).returns(String) }
      def git_remote(repo)
        output, status = Open3.capture2e("git", "-C", repo, "remote", "get-url", "origin")
        checked_output(output, status)
      end

      sig { params(repo: String, branch: String, path: String).void }
      def git_worktree_add(repo, branch, path)
        output, status = Open3.capture2e("git", "-C", repo, "worktree", "add", "-b", branch, path, "HEAD")
        checked_output(output, status)
      end

      sig { params(repo: String).returns(String) }
      def git_branch(repo)
        output, status = Open3.capture2e("git", "-C", repo, "branch", "--show-current")
        checked_output(output, status)
      end

      sig { params(repo: String).returns(String) }
      def git_common_dir(repo)
        output, status = Open3.capture2e("git", "-C", repo, "rev-parse", "--path-format=absolute", "--git-common-dir")
        checked_output(output, status)
      end

      sig { params(output: String, status: Process::Status).returns(String) }
      def checked_output(output, status)
        raise ArgumentError, "Git validation failed" unless status.success?

        output.strip
      end
    end
  end
end

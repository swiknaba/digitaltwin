# frozen_string_literal: true

require "fileutils"
require "open3"
module Domains
  module Projects
    class Workspace
      def initialize(root: ENV.fetch("WORKSPACE_ROOT", "/workspace/repos"),
                     worktrees_root: ENV.fetch("WORKTREE_ROOT", "/workspace/worktrees"))
        @root = File.realpath(root)
        @trees = File.realpath(worktrees_root)
      end

      def resolve(slug:)
        RepositoryIdentity.slug!(slug)
        path = contained!(@root, File.join(@root, slug))
        raise ArgumentError, "Repository missing: choose clone/create_private/stop" unless File.directory?(path)
        raise ArgumentError, "Expected repository root" unless File.realpath(git(path, "rev-parse",
                                                                                 "--show-toplevel")) == path

        RepositoryIdentity.remote!(git(path, "remote", "get-url", "origin"), slug)
        path
      end

      def destination(slug:)
        RepositoryIdentity.slug!(slug)
        contained!(@root, File.join(@root, slug))
      end

      def for_workflow(slug:, workflow_id:, branch:)
        raise ArgumentError,
              "Invalid workflow UUID/branch" unless workflow_id.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/) && branch == "digitaltwin/#{workflow_id}"

        path = contained!(@trees, File.join(@trees, workflow_id))
        repo = resolve(slug: slug)
        git(repo, "worktree", "add", "-b", branch, path, "HEAD") unless File.exist?(path)
        raise ArgumentError, "Worktree branch mismatch" unless git(path, "branch", "--show-current") == branch

        common = git(path, "rev-parse", "--path-format=absolute", "--git-common-dir")
        expected = git(repo, "rev-parse", "--path-format=absolute", "--git-common-dir")
        raise ArgumentError, "Worktree repository mismatch" unless File.realpath(common) == File.realpath(expected)
        raise ArgumentError, "Worktree root mismatch" unless File.realpath(git(path, "rev-parse",
                                                                               "--show-toplevel")) == path

        RepositoryIdentity.remote!(git(path, "remote", "get-url", "origin"), slug)
        path
      end
      private def contained!(root, path)
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
      private def git(repo, *args)
        output, status = Open3.capture2e("git", "-C", repo, *args)
        raise ArgumentError, "Git validation failed" unless status.success?

        output.strip
      end
    end
  end
end

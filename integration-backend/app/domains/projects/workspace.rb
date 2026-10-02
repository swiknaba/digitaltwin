# typed: strict
# frozen_string_literal: true

module Domains
  module Projects
    class Workspace
      extend T::Sig

      UUID_PATTERN = T.let(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/, Regexp)

      sig { params(root: String, worktrees_root: String, git: Adapters::Git::Worktrees).void }
      def initialize(root: ENV.fetch("WORKSPACE_ROOT", "/workspace/repos"),
                     worktrees_root: ENV.fetch("WORKTREE_ROOT", "/workspace/worktrees"), git: Adapters::Git::Worktrees.new)
        @root = T.let(File.realpath(root), String)
        @trees = T.let(File.realpath(worktrees_root), String)
        @git = git
      end

      sig { params(slug: String).returns(String) }
      def resolve(slug:)
        RepositoryIdentity.slug!(slug)
        path = contained!(@root, File.join(@root, slug))
        raise ArgumentError, "Repository missing: choose clone/create_private/stop" unless File.directory?(path)
        raise ArgumentError, "Expected repository root" unless File.realpath(@git.top_level(repo: path)) == path

        RepositoryIdentity.remote!(@git.remote(repo: path), slug)
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
        @git.add(repo: repo, branch: branch, path: path) unless File.exist?(path)
        raise ArgumentError, "Worktree branch mismatch" unless @git.branch(repo: path) == branch

        common = @git.common_dir(repo: path)
        expected = @git.common_dir(repo: repo)
        raise ArgumentError, "Worktree repository mismatch" unless File.realpath(common) == File.realpath(expected)
        raise ArgumentError, "Worktree root mismatch" unless File.realpath(@git.top_level(repo: path)) == path

        RepositoryIdentity.remote!(@git.remote(repo: path), slug)
        path
      end

      sig { params(root: String, path: String).returns(String) }
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
    end
  end
end

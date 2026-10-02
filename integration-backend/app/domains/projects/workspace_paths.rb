# typed: strict
# frozen_string_literal: true

module Domains
  module Projects
    # Pure path rules for repository checkouts and workflow worktrees. Every
    # returned path lies inside its root and crosses no symlink. The roots are
    # real paths, resolved once at construction. Raises ArgumentError on a rule
    # violation. Runs no git command.
    class WorkspacePaths
      extend T::Sig

      UUID_PATTERN = T.let(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/, Regexp)

      sig { params(root: String, worktrees_root: String).void }
      def initialize(root: ENV.fetch("WORKSPACE_ROOT", "/workspace/repos"),
                     worktrees_root: ENV.fetch("WORKTREE_ROOT", "/workspace/worktrees"))
        @root = T.let(File.realpath(root), String)
        @trees = T.let(File.realpath(worktrees_root), String)
      end

      sig { params(slug: String).returns(String) }
      def repository(slug:)
        RepositoryIdentity.slug!(slug)
        contained!(root: @root, path: File.join(@root, slug))
      end

      sig { params(slug: String, workflow_id: String).returns(String) }
      def worktree(slug:, workflow_id:)
        raise ArgumentError, "Invalid workflow UUID/branch" unless workflow_id.match?(UUID_PATTERN)

        RepositoryIdentity.slug!(slug)
        contained!(root: @trees, path: File.join(@trees, workflow_id))
      end

      # The root to contain is either configured root, so the caller passes it.
      sig { params(root: String, path: String).returns(String) }
      def contained!(root:, path:)
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

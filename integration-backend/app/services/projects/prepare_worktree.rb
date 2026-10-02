# typed: strict
# frozen_string_literal: true

module Services
  module Projects
    # Creates or revalidates the per-workflow git worktree of a repository.
    # Reruns after a restart check the same branch, common git dir and remote.
    class PrepareWorktree
      extend T::Sig

      sig do
        params(
          paths: Domains::Projects::WorkspacePaths,
          resolve_repository: ResolveRepository,
          git: Adapters::Git::Worktrees
        ).void
      end
      def initialize(paths: Domains::Projects::WorkspacePaths.new, resolve_repository: ResolveRepository.new(paths: paths),
                     git: Adapters::Git::Worktrees.new)
        @paths = paths
        @resolve_repository = resolve_repository
        @git = git
      end

      sig { params(slug: String, workflow_id: String, branch: String).returns(Kirei::Services::Result[String]) }
      def call(slug:, workflow_id:, branch:)
        Kirei::Services::Runner.call(self.class.name.to_s) do
          raise ArgumentError, "Invalid workflow id/branch" unless branch == "digitaltwin/#{workflow_id}"

          path = @paths.worktree(slug: slug, workflow_id: workflow_id)
          resolved = @resolve_repository.call(slug: slug)
          next Kirei::Services::Result.new(errors: resolved.errors) if resolved.failed?

          repo = resolved.result
          @git.add(repo: repo, branch: branch, path: path) unless File.exist?(path)
          raise ArgumentError, "Worktree branch mismatch" unless @git.branch(repo: path) == branch

          common = @git.common_dir(repo: path)
          expected = @git.common_dir(repo: repo)
          raise ArgumentError, "Worktree repository mismatch" unless File.realpath(common) == File.realpath(expected)
          raise ArgumentError, "Worktree root mismatch" unless File.realpath(@git.top_level(repo: path)) == path

          Domains::Projects::RepositoryIdentity.remote!(@git.remote(repo: path), slug)
          Kirei::Services::Result.new(result: path)
        rescue ArgumentError => error
          Kirei::Services::Result.new(errors: Platform::Failure.call(code: Domains::Projects::Dto::ErrorCode::WorkspaceRejected, detail: error.message))
        end
      end
    end
  end
end

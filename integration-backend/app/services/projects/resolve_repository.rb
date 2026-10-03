# typed: strict
# frozen_string_literal: true

module Services
  module Projects
    # Verifies that a checkout exists at its contained path, is the repository
    # root, and has the remote identity that the slug names.
    class ResolveRepository
      extend T::Sig

      sig { params(paths: Domains::Projects::WorkspacePaths, git: Adapters::Git::Worktrees).void }
      def initialize(paths:, git: Adapters::Git::Worktrees.new)
        @paths = paths
        @git = git
      end

      sig { params(slug: String).returns(Kirei::Services::Result[String]) }
      def call(slug:)
        Kirei::Services::Runner.call(self.class.name.to_s) do
          path = @paths.repository(slug: slug)
          raise ArgumentError, "Repository missing: choose clone/create_private/stop" unless File.directory?(path)
          raise ArgumentError, "Expected repository root" unless File.realpath(@git.top_level(repo: path)) == path

          Domains::Projects::RepositoryIdentity.remote!(@git.remote(repo: path), slug)
          Kirei::Services::Result.new(result: path)
        rescue ArgumentError => error
          # Path-rule violations and local git validation failures are expected
          # rejections; their messages are the operator-facing detail.
          Kirei::Services::Result.new(errors: Platform::Failure.call(code: Domains::Projects::Dto::ErrorCode::WorkspaceRejected, detail: error.message))
        end
      end
    end
  end
end

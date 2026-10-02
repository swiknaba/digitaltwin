# typed: strict
# frozen_string_literal: true

module Services
  module Projects
    # Maps a chat channel to a GitHub repository on behalf of a verified human
    # channel member. Clone and repository creation run before the short
    # registration write, never under a lock.
    class Enroll
      extend T::Sig

      Dto = Domains::Projects::Dto
      Outcome = T.type_alias { Kirei::Services::Result[Dto::Enrollment] }

      sig do
        params(
          paths: Domains::Projects::WorkspacePaths,
          directory: Domains::Projects::Directory,
          register: Domains::Projects::Register,
          resolve_repository: ResolveRepository,
          git_repos: Adapters::Git::Repositories
        ).void
      end
      def initialize(paths: Domains::Projects::WorkspacePaths.new, directory: Domains::Projects::Directory.new,
                     register: Domains::Projects::Register.new, resolve_repository: ResolveRepository.new(paths: paths),
                     git_repos: Adapters::Git::Repositories.new)
        @paths = paths
        @directory = directory
        @register = register
        @resolve_repository = resolve_repository
        @git_repos = git_repos
      end

      sig { params(actor: Domains::Messaging::Dto::VerifiedActor, channel_id: String, slug: String, choice: Dto::EnrollChoice).returns(Outcome) }
      def call(actor:, channel_id:, slug:, choice:)
        Kirei::Services::Runner.call(self.class.name.to_s) do
          unless actor.member && !actor.bot && actor.channel_id == channel_id
            next failure(Dto::ErrorCode::MembershipRequired, "Verified human channel membership required")
          end
          next failure(Dto::ErrorCode::InvalidSlug, "Expected owner/repository slug") unless Domains::Projects::RepositoryIdentity.slug?(slug)

          existing = @directory.for_channel(channel_id: channel_id)
          next retain(existing, slug) if existing

          enroll(channel_id: channel_id, slug: slug, choice: choice)
        rescue ArgumentError => error
          failure(Dto::ErrorCode::WorkspaceRejected, error.message)
        end
      end

      sig { params(existing: Dto::Project, slug: String).returns(Outcome) }
      private def retain(existing, slug)
        return failure(Dto::ErrorCode::ChannelEnrolledElsewhere, "Channel already enrolled to another repository") unless existing.slug == slug

        resolved = @resolve_repository.call(slug: slug)
        return Kirei::Services::Result.new(errors: resolved.errors) if resolved.failed?

        success(Dto::EnrollmentStatus::Retained, "Channel mapping retained")
      end

      sig { params(channel_id: String, slug: String, choice: Dto::EnrollChoice).returns(Outcome) }
      private def enroll(channel_id:, slug:, choice:)
        path = @paths.repository(slug: slug)
        unless File.exist?(path)
          return success(Dto::EnrollmentStatus::Blocked, "Choose clone/create_private/stop") if choice == Dto::EnrollChoice::Stop

          @git_repos.create_private(slug: slug) if choice == Dto::EnrollChoice::CreatePrivate
          FileUtils.mkdir_p(File.dirname(path))
          @git_repos.clone(slug: slug, destination: path)
        end
        resolved = @resolve_repository.call(slug: slug)
        return Kirei::Services::Result.new(errors: resolved.errors) if resolved.failed?

        registered = @register.call(channel_id: channel_id, slug: slug, remote_identity: "github.com/#{slug.downcase}", workspace: resolved.result)
        return Kirei::Services::Result.new(errors: registered.errors) if registered.failed?

        success(Dto::EnrollmentStatus::Enrolled, "Repository enrolled")
      end

      sig { params(status: Dto::EnrollmentStatus, detail: String).returns(Outcome) }
      private def success(status, detail)
        Kirei::Services::Result.new(result: Dto::Enrollment.new(status: status, detail: detail))
      end

      sig { params(code: Dto::ErrorCode, detail: String).returns(Outcome) }
      private def failure(code, detail)
        Kirei::Services::Result.new(errors: Platform::Failure.call(code: code, detail: detail))
      end
    end
  end
end

# typed: strict
# frozen_string_literal: true

module Domains
  module Projects
    # Records a channel-to-repository mapping. A channel, slug, remote identity
    # and workspace each map to at most one project.
    class Register
      extend T::Sig

      sig { params(channel_id: String, slug: String, remote_identity: String, workspace: String).returns(Kirei::Services::Result[Dto::Project]) }
      def call(channel_id:, slug:, remote_identity:, workspace:)
        project = Entities::Project.db.transaction(savepoint: true) do
          Entities::Project.create(id: SecureRandom.uuid, channel_id: channel_id, slug: slug, remote_identity: remote_identity, workspace: workspace)
        end
        Kirei::Services::Result.new(result: T.must(Directory.new.find(id: project.id)))
      rescue Sequel::UniqueConstraintViolation
        Kirei::Services::Result.new(errors: Platform::Failure.call(code: Dto::ErrorCode::AlreadyEnrolled, detail: "Repository/channel already enrolled"))
      end
    end
  end
end

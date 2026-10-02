# typed: strict
# frozen_string_literal: true

module Domains
  module Projects
    # Read access to enrolled projects.
    class Directory
      extend T::Sig

      sig { params(id: String).returns(T.nilable(Dto::Project)) }
      def find(id:)
        project = Entities::Project.find_by(id: id)
        project && project_dto(project)
      end

      sig { params(channel_id: String).returns(T.nilable(Dto::Project)) }
      def for_channel(channel_id:)
        project = Entities::Project.find_by(channel_id: channel_id)
        project && project_dto(project)
      end

      sig { returns(T::Array[Dto::Project]) }
      def all
        Entities::Project.all.map { |project| project_dto(project) }
      end

      sig { params(entity: Entities::Project).returns(Dto::Project) }
      private def project_dto(entity)
        Dto::Project.new(id: entity.id, channel_id: entity.channel_id, slug: entity.slug,
                         remote_identity: entity.remote_identity, workspace: entity.workspace)
      end
    end
  end
end

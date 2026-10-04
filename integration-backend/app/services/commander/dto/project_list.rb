# typed: strict
# frozen_string_literal: true

module Services
  module Commander
    module Dto
      # list_projects: the enrolled projects the request's human can access.
      class ProjectList < T::Struct
        include Kirei::Domain::ValueObject

        const :projects, T::Array[Domains::Projects::Dto::Project]
      end
    end
  end
end

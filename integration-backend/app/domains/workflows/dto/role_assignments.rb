# typed: strict
# frozen_string_literal: true

module Domains
  module Workflows
    module Dto
      # Workflow role configurations. Workflows persist the whole object, so an
      # optional commander entry stays in `role_configurations` as today.
      class RoleAssignments < T::Struct
        include Kirei::Domain::ValueObject

        const :writer, RoleConfig
        const :reviewer, RoleConfig
        const :commander, T.nilable(RoleConfig), default: nil
      end
    end
  end
end

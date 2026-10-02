# typed: strict
# frozen_string_literal: true

module Domains
  module Workflows
    module Dto
      # The parsed ROLE_CONFIG_FILE. Workflows persist the whole object, so an
      # optional controller entry stays in `role_configurations` as today.
      class RoleAssignments < T::Struct
        include Kirei::Domain::ValueObject

        const :writer, RoleConfig
        const :reviewer, RoleConfig
        const :controller, T.nilable(RoleConfig), default: nil
      end
    end
  end
end

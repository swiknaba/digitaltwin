# typed: strict
# frozen_string_literal: true

module Domains
  module Workflows
    module Dto
      # One role's agent runtime from ROLE_CONFIG_FILE. Prop order is the
      # canonical key order of the start request digest.
      class RoleConfig < T::Struct
        include Kirei::Domain::ValueObject

        const :cli, String
        const :provider, String
        const :model, String
        const :family, String
        const :launch_args, T::Array[String]
      end
    end
  end
end

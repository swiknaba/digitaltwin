# typed: strict
# frozen_string_literal: true

module Domains
  module Workflows
    module Entities
      class RoleConfig < T::Struct
        const :cli, String
        const :provider, String
        const :model, String
        const :family, String
      end
    end
  end
end

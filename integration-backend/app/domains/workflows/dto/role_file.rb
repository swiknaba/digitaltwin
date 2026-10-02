# typed: strict
# frozen_string_literal: true

module Domains
  module Workflows
    module Dto
      # The parsed ROLE_CONFIG_FILE. A controller-only file is valid; Writer
      # and Reviewer entries are needed only to start workflows.
      class RoleFile < T::Struct
        extend T::Sig
        include Kirei::Domain::ValueObject

        const :writer, T.nilable(RoleConfig), default: nil
        const :reviewer, T.nilable(RoleConfig), default: nil
        const :controller, T.nilable(RoleConfig), default: nil

        # The workflow role assignments, or nil when Writer or Reviewer is missing.
        sig { returns(T.nilable(RoleAssignments)) }
        def assignments
          writer = self.writer
          reviewer = self.reviewer
          return nil unless writer && reviewer

          RoleAssignments.new(writer: writer, reviewer: reviewer, controller: controller)
        end
      end
    end
  end
end

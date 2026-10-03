# typed: strict
# frozen_string_literal: true

module Services
  module Commands
    module Dto
      # `@<agent> recover-session <operation_id> <pane_id>`.
      class RecoverSession < T::Struct
        include Kirei::Domain::ValueObject

        const :operation_id, String
        const :pane_id, String
      end
    end
  end
end

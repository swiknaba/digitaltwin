# typed: strict
# frozen_string_literal: true

module Domains
  module Commander
    module Dto
      # Backend-verified instruction identity. Request text never supplies it.
      class InstructionAttribution < T::Struct
        include Kirei::Domain::ValueObject

        const :effective_sender, String
        const :origin_inbox_id, String
        const :origin_user_id, String
        const :mode, String
      end
    end
  end
end

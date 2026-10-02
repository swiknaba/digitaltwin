# typed: strict
# frozen_string_literal: true

module Services
  module Reviews
    module Dto
      # A callback caller identified by its session credential.
      class BearerToken < T::Struct
        include Kirei::Domain::ValueObject

        const :token, String
      end
    end
  end
end

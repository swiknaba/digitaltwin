# typed: strict
# frozen_string_literal: true

module Domains
  module Projects
    module Dto
      # Successful or blocked enrollment. Rejections are failure results.
      class Enrollment < T::Struct
        include Kirei::Domain::ValueObject

        const :status, EnrollmentStatus
        const :detail, String
      end
    end
  end
end

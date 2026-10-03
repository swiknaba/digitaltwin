# typed: strict
# frozen_string_literal: true

module Domains
  module Projects
    module Dto
      class EnrollmentStatus < T::Enum
        enums do
          Enrolled = new("enrolled")
          Retained = new("retained")
          Blocked = new("blocked")
        end
      end
    end
  end
end

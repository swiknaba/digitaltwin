# typed: strict
# frozen_string_literal: true

module Platform
  module Audit
    module Dto
      class Receipt < T::Struct
        include Kirei::Domain::ValueObject

        const :action, String
        const :details, Platform::Json::Scalars
      end
    end
  end
end

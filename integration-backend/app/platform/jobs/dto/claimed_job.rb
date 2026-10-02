# typed: strict
# frozen_string_literal: true

module Platform
  module Jobs
    module Dto
      class ClaimedJob < T::Struct
        include Kirei::Domain::ValueObject

        const :id, String
        const :kind, JobKind
        const :payload, Platform::Json::Scalars
        const :attempts, Integer
        const :lease, Lease
      end
    end
  end
end

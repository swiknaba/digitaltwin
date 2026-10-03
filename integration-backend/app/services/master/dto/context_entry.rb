# typed: strict
# frozen_string_literal: true

module Services
  module Master
    module Dto
      # One recent verified human message the request's human can access.
      class ContextEntry < T::Struct
        include Kirei::Domain::ValueObject

        const :inbox_id, String
        const :channel_id, String
        const :thread_id, String
        const :text, String
      end
    end
  end
end

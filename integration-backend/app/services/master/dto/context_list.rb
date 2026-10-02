# typed: strict
# frozen_string_literal: true

module Services
  module Master
    module Dto
      # read_context: recent verified human messages, newest first.
      class ContextList < T::Struct
        include Kirei::Domain::ValueObject

        const :entries, T::Array[ContextEntry]
      end
    end
  end
end

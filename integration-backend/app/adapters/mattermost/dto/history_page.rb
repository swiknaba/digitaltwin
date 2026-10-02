# typed: strict
# frozen_string_literal: true

module Adapters
  module Mattermost
    module Dto
      class HistoryPage < T::Struct
        include Kirei::Domain::ValueObject

        const :order, T::Array[String]
        const :entries, T::Array[HistoryEntry]
      end
    end
  end
end

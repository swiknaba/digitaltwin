# typed: strict
# frozen_string_literal: true

module Domains
  module FutureTasks
    module Dto
      class TaskPage < T::Struct
        include Kirei::Domain::ValueObject

        const :items, T::Array[TaskView]
        const :next_cursor, T.nilable(String), default: nil
      end
    end
  end
end

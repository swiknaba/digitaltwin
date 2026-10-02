# typed: strict
# frozen_string_literal: true

module Services
  module Commands
    module Dto
      # `@<worker> <action>`. The start re-verification also requires a single space separator.
      class WorkerCommand < T::Struct
        include Kirei::Domain::ValueObject

        const :action, WorkerAction
        const :single_space_separator, T::Boolean
      end
    end
  end
end

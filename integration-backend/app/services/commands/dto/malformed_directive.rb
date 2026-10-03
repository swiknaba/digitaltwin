# typed: strict
# frozen_string_literal: true

module Services
  module Commands
    module Dto
      # Starts with `@<agent> approve` or `@<agent> route` but matches neither exact
      # grammar. Routing handles it deterministically instead of the Master model.
      class MalformedDirective < T::Struct
        include Kirei::Domain::ValueObject
      end
    end
  end
end

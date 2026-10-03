# typed: strict
# frozen_string_literal: true

module Adapters
  module Herdr
    module Dto
      class Workspace < T::Struct
        include Kirei::Domain::ValueObject

        const :workspace_id, String
        const :root_pane_id, String
      end
    end
  end
end

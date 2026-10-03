# typed: strict
# frozen_string_literal: true

module Adapters
  module Herdr
    module Dto
      # One entry of the unfiltered pane inventory.
      class PaneSummary < T::Struct
        include Kirei::Domain::ValueObject

        const :pane_id, String
      end
    end
  end
end

# typed: strict
# frozen_string_literal: true

module Domains
  module Commander
    module Dto
      # Lifecycle of a Master request. Uncertain requests may have reached the
      # Master conversation and need human reconciliation.
      class MasterRequestState < T::Enum
        enums do
          Queued = new("queued")
          Active = new("active")
          Complete = new("complete")
          Uncertain = new("uncertain")
        end
      end
    end
  end
end

# typed: strict
# frozen_string_literal: true

module Services
  module Inbound
    module Dto
      # Classification of an ingested delivery.
      class IngestStatus < T::Enum
        enums do
          Accepted = new("accepted")
          Rejected = new("rejected")
          Blocked = new("blocked")
        end
      end
    end
  end
end

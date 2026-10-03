# typed: strict
# frozen_string_literal: true

module Domains
  module Workflows
    module Dto
      # The `workflow_requests.state` values. Sending and uncertain need human
      # reconciliation before the start can continue.
      class RequestState < T::Enum
        enums do
          Queued = new("queued")
          Sending = new("sending")
          Uncertain = new("uncertain")
          Bound = new("bound")
          Blocked = new("blocked")
        end
      end
    end
  end
end

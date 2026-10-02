# typed: strict
# frozen_string_literal: true

module Domains
  module Workflows
    module Dto
      # A verified message held back while the workflow is paused or in review.
      class QueuedMessageView < T::Struct
        include Kirei::Domain::ValueObject

        const :id, Integer
        const :workflow_id, String
        const :inbox_id, Integer
        const :workflow_version, Integer
      end
    end
  end
end

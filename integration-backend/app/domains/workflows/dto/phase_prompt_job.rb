# typed: strict
# frozen_string_literal: true

module Domains
  module Workflows
    module Dto
      # Payload of workflow.phase_prompt jobs.
      class PhasePromptJob < T::Struct
        include Kirei::Domain::ValueObject

        const :workflow_id, String
        const :version, Integer
      end
    end
  end
end

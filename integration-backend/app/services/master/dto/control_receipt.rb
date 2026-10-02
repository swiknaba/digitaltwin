# typed: strict
# frozen_string_literal: true

module Services
  module Master
    module Dto
      # workflow_control: the control job is queued for the socket-owning worker.
      class ControlReceipt < T::Struct
        include Kirei::Domain::ValueObject

        const :status, String, default: "queued"
      end
    end
  end
end

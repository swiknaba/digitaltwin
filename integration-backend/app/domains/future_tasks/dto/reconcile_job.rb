# typed: strict
# frozen_string_literal: true

module Domains
  module FutureTasks
    module Dto
      class ReconcileJob < T::Struct
        include Kirei::Domain::ValueObject

        const :execution_id, String
      end
    end
  end
end

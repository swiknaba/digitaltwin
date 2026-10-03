# typed: strict
# frozen_string_literal: true

module Domains
  module Sessions
    module Dto
      # One start or stop operation of a session. Each kind happens at most once per session.
      class OperationView < T::Struct
        include Kirei::Domain::ValueObject

        const :id, String
        const :session_id, String
        const :kind, OperationKind
        const :state, OperationState
        const :reason, T.nilable(String)
      end
    end
  end
end

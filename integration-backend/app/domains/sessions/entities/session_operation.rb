# typed: strict
# frozen_string_literal: true

# == Schema Info
#
# Table name: session_operations
#
#  id                  :text                not null, primary key
#  session_id          :text                not null
#  kind                :text                not null
#  state               :text                not null
#  reason              :text                null
#

module Domains
  module Sessions
    module Entities
      class SessionOperation < T::Struct
        extend T::Sig
        include Kirei::Model
        include Kirei::Domain::Entity

        const :id, String
        const :session_id, String
        const :kind, Dto::OperationKind
        const :state, Dto::OperationState, default: Dto::OperationState::Queued
        const :reason, T.nilable(String), default: nil
      end
    end
  end
end

# typed: strict
# frozen_string_literal: true

# == Schema Info
#
# Table name: commander_requests
#
#  id                  :text                not null, primary key
#  inbox_id            :text                not null
#  session_id          :text                not null
#  credential_digest   :text                not null
#  expires_at          :timestamp without time zone, not null
#  state               :text                not null
#  reason              :text                null
#

module Domains
  module Commander
    module Entities
      class CommanderRequest < T::Struct
        include Kirei::Model
        include Kirei::Domain::Entity

        const :id, String
        const :inbox_id, String
        const :session_id, String
        const :credential_digest, String
        const :expires_at, Time
        const :state, Dto::CommanderRequestState, default: Dto::CommanderRequestState::Queued
        const :reason, T.nilable(String), default: nil
      end
    end
  end
end

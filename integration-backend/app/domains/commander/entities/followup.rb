# typed: strict
# frozen_string_literal: true

# == Schema Info
#
# Table name: followups
#
#  id                  :text                not null, primary key
#  inbox_id            :text                not null, unique
#  workflow_id         :text                not null
#  session_id          :text                null
#  generation          :integer             null
#  status              :text                not null
#  reason              :text                null
#  evidence            :jsonb               not null
#  created_at          :timestamp without time zone, not null
#  delivered_at        :timestamp without time zone, null
#

module Domains
  module Commander
    module Entities
      class Followup < T::Struct
        include Kirei::Model
        include Kirei::Domain::Entity

        const :id, String
        const :inbox_id, String
        const :workflow_id, String
        const :session_id, T.nilable(String), default: nil
        const :generation, T.nilable(Integer), default: nil
        const :status, Dto::FollowupStatus, default: Dto::FollowupStatus::Queued
        const :reason, T.nilable(String), default: nil
        const :evidence, Dto::RoutingEvidence
        # Local time: the column has no zone, and Sequel stores the wall clock.
        const :created_at, Time, factory: -> { Time.now }
        const :delivered_at, T.nilable(Time), default: nil
      end
    end
  end
end

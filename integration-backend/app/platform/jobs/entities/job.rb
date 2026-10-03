# typed: strict
# frozen_string_literal: true

# == Schema Info
#
# Table name: jobs
#
#  id                  :text                not null, primary key
#  dispatch_key        :text                not null
#  kind                :text                not null
#  payload             :jsonb               not null
#  status              :text                not null
#  attempts            :integer             not null
#  worker_id           :text                null
#  lease_token         :text                null
#  lease_expires_at    :timestamp without time zone, null
#  available_at        :timestamp without time zone, not null
#  effect_started_at   :timestamp without time zone, null
#  last_error          :text                null
#  created_at          :timestamp without time zone, not null
#

module Platform
  module Jobs
    module Entities
      class Job < T::Struct
        include Kirei::Model
        include Kirei::Domain::Entity

        const :id, String
        const :kind, Dto::JobKind
        const :payload, Platform::Json::Scalars
        const :dispatch_key, String
        const :status, Dto::JobStatus, default: Dto::JobStatus::Pending
        const :worker_id, T.nilable(String), default: nil
        const :lease_token, T.nilable(String), default: nil
        const :lease_expires_at, T.nilable(Time), default: nil
        const :attempts, Integer, default: 0
        const :available_at, Time
        const :effect_started_at, T.nilable(Time), default: nil
        const :last_error, T.nilable(String), default: nil
      end
    end
  end
end

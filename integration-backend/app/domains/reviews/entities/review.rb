# typed: strict
# frozen_string_literal: true

# == Schema Info
#
# Table name: reviews
#
#  id                     :text                not null, primary key
#  workflow_id            :text                not null
#  gate                   :text                not null
#  round                  :integer             not null
#  target_commit          :text                not null
#  base_commit            :text                null
#  review_commit          :text                null
#  review_path            :text                not null
#  verdict                :text                null
#  reviewer_configuration :jsonb               not null
#  created_at             :timestamp without time zone, not null
#  dispatch_state         :text                not null
#

module Domains
  module Reviews
    module Entities
      class Review < T::Struct
        include Kirei::Model
        include Kirei::Domain::Entity

        const :id, String
        const :workflow_id, String
        const :gate, Workflows::Dto::Gate
        const :round, Integer
        const :target_commit, String
        const :base_commit, T.nilable(String), default: nil
        const :review_commit, T.nilable(String), default: nil
        const :review_path, String
        const :verdict, T.nilable(Dto::Verdict), default: nil
        const :reviewer_configuration, Workflows::Dto::RoleConfig
        const :created_at, Time, factory: -> { Time.now.utc }
        const :dispatch_state, Dto::DispatchState, default: Dto::DispatchState::Queued
      end
    end
  end
end

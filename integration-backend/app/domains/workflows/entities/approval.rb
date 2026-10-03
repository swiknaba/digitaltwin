# typed: strict
# frozen_string_literal: true

# == Schema Info
#
# Table name: approvals
#
#  id                  :text                not null, primary key
#  workflow_id         :text                not null
#  kind                :text                not null
#  target_commit       :text                not null
#  user_id             :text                not null
#  channel_id          :text                not null
#  post_id             :text                not null
#  created_at          :timestamp without time zone, not null
#

module Domains
  module Workflows
    module Entities
      # `kind` holds the gate; the approval_kind constraint allows spec and plan.
      class Approval < T::Struct
        extend T::Sig
        include Kirei::Model
        include Kirei::Domain::Entity

        const :id, String
        const :workflow_id, String
        const :kind, Dto::Gate
        const :target_commit, String
        const :user_id, String
        const :channel_id, String
        const :post_id, String
        const :created_at, Time
      end
    end
  end
end

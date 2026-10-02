# typed: strict
# frozen_string_literal: true

# == Schema Info
#
# Table name: queued_messages
#
#  id                  :text                not null, primary key
#  workflow_id         :text                not null
#  inbox_id            :text                not null
#  workflow_version    :integer             not null
#  created_at          :timestamp without time zone, not null
#

module Domains
  module Workflows
    module Entities
      class QueuedMessage < T::Struct
        extend T::Sig
        include Kirei::Model
        include Kirei::Domain::Entity

        const :id, String
        const :workflow_id, String
        const :inbox_id, String
        const :workflow_version, Integer
        const :created_at, Time
      end
    end
  end
end

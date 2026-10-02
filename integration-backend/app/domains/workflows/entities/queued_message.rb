# typed: strict
# frozen_string_literal: true

# == Schema Info
#
# Table name: queued_messages
#
#  id                  :integer             not null, primary key
#  workflow_id         :text                not null
#  inbox_id            :integer             not null
#  workflow_version    :integer             not null
#

module Domains
  module Workflows
    module Entities
      class QueuedMessage < T::Struct
        include Kirei::Model
        include Kirei::Domain::Entity

        const :id, Integer
        const :workflow_id, String
        const :inbox_id, Integer
        const :workflow_version, Integer
      end
    end
  end
end

# typed: strict
# frozen_string_literal: true

# == Schema Info
#
# Table name: conversation_bindings
#
#  channel_id          :text                not null, primary key
#  thread_id           :text                not null, primary key
#  user_id             :text                not null, primary key
#  workflow_id         :text                not null
#  inbox_id            :text                not null
#  updated_at          :timestamp without time zone, not null
#

module Domains
  module Commander
    module Entities
      # The primary key is (channel_id, thread_id, user_id), not id. Kirei's
      # #create, #update and #delete key on id, so Bindings writes through an
      # insert_conflict upsert on the composite key.
      class ConversationBinding < T::Struct
        include Kirei::Model

        const :channel_id, String
        const :thread_id, String
        const :user_id, String
        const :workflow_id, String
        const :inbox_id, String
        const :updated_at, Time
      end
    end
  end
end

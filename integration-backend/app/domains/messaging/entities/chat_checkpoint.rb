# typed: strict
# frozen_string_literal: true

# == Schema Info
#
# Table name: chat_checkpoints
#
#  channel_id          :text                not null, primary key
#  post_revision       :bigint              not null
#

module Domains
  module Messaging
    module Entities
      # The primary key is channel_id, not id. Kirei's #update and #delete key
      # on id, so writes use `ChatCheckpoint.query` filtered by channel_id or
      # an insert_conflict upsert on channel_id.
      class ChatCheckpoint < T::Struct
        extend T::Sig
        include Kirei::Model

        sig { override.returns(String) }
        def self.table_name = "chat_checkpoints"

        const :channel_id, String
        const :post_revision, Integer, default: 0
      end
    end
  end
end

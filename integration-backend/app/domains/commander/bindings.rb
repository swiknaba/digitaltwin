# typed: strict
# frozen_string_literal: true

module Domains
  module Commander
    # A human's current workflow context per chat thread. Routing reuses a
    # recent binding for later messages in the same thread.
    class Bindings
      extend T::Sig

      KEY = T.let(%i[channel_id thread_id user_id].freeze, T::Array[Symbol])

      # Upserts one binding per thread. The table has a composite primary key
      # and no id, so this uses insert_conflict instead of Kirei #create/#update.
      sig { params(channel_id: String, thread_ids: T::Array[String], user_id: String, workflow_id: String, inbox_id: String, at: Time).void }
      def bind(channel_id:, thread_ids:, user_id:, workflow_id:, inbox_id:, at:)
        thread_ids.each do |thread_id|
          Entities::ConversationBinding.query.insert_conflict(target: KEY, update: { workflow_id: workflow_id, inbox_id: inbox_id, updated_at: at })
                                       .insert(channel_id: channel_id, thread_id: thread_id, user_id: user_id, workflow_id: workflow_id, inbox_id: inbox_id,
                                               updated_at: at)
        end
      end

      sig { params(channel_id: String, thread_id: String, user_id: String).returns(T.nilable(Dto::BindingView)) }
      def find(channel_id:, thread_id:, user_id:)
        entity = Entities::ConversationBinding.find_by(channel_id: channel_id, thread_id: thread_id, user_id: user_id)
        entity && Dto::BindingView.new(channel_id: entity.channel_id, thread_id: entity.thread_id, user_id: entity.user_id, workflow_id: entity.workflow_id,
                                       inbox_id: entity.inbox_id, updated_at: entity.updated_at)
      end

      # Whether a thread context created by `inbox_id` binds `workflow_id`.
      sig { params(inbox_id: String, workflow_id: String).returns(T::Boolean) }
      def bound?(inbox_id:, workflow_id:) = !Entities::ConversationBinding.query.where(inbox_id: inbox_id, workflow_id: workflow_id).empty?
    end
  end
end

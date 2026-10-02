# typed: strict
# frozen_string_literal: true

module Domains
  module Mattermost
    class VerifiedDelivery < T::Struct
      TransportValue = T.type_alias { T.any(String, Integer, T::Boolean, NilClass) }
      TransportResponse = T.type_alias { T::Hash[String, TransportValue] }

      module Transport
        extend T::Helpers

        interface!

        extend T::Sig

        sig { abstract.params(path: String).returns(TransportResponse) }
        def get(path); end
      end

      class Post < T::Struct
        const :id, String
        const :channel_id, String
        const :user_id, String
        const :root_id, T.nilable(String)
        const :message, String
        const :create_at, Integer
        const :update_at, Integer
        const :delete_at, Integer
      end

      class Channel < T::Struct
        const :id, String
      end

      class Membership < T::Struct
        const :channel_id, String
        const :user_id, String
      end

      class User < T::Struct
        const :id, String
        const :delete_at, Integer
        const :bot, T::Boolean
      end

      const :channel_id, String
      const :post_id, String
      const :thread_id, String
      const :actor, Domains::Workflows::Entities::Actor
      const :event_kind, String
      const :post_revision, Integer
      const :body, String
      const :root_post, T::Boolean
    end
  end
end

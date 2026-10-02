# typed: strict
# frozen_string_literal: true

module Domains
  module Mattermost
    class VerifiedDelivery < T::Struct
      # HTTP JSON is a transport boundary; endpoint parsers validate fields
      # before they become a verified delivery identity.
      TransportValue = T.type_alias { Object }
      TransportResponse = T.type_alias { T::Hash[String, TransportValue] }

      module Transport
        extend T::Helpers

        interface!

        extend T::Sig

        sig { abstract.params(path: String).returns(TransportResponse) }
        def get(path); end
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

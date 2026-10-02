# typed: strict
# frozen_string_literal: true

module Adapters
  module Mattermost
    module Dto
      # One post of a history page, keyed as the server keyed it.
      # `canonical_json` is the post JSON as received; quarantine digests use it.
      # `post` is nil when translation failed, and `rejection` holds the reason.
      # `post_id` is the raw `id` value when it is a String.
      class HistoryEntry < T::Struct
        include Kirei::Domain::ValueObject

        const :key, String
        const :canonical_json, String
        const :post_id, T.nilable(String)
        const :post, T.nilable(Post)
        const :rejection, T.nilable(String)
      end
    end
  end
end

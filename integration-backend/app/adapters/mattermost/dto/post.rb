# typed: strict
# frozen_string_literal: true

module Adapters
  module Mattermost
    module Dto
      # Only `digitaltwin_*` props with String values are kept.
      class Post < T::Struct
        include Kirei::Domain::ValueObject

        const :id, String
        const :channel_id, String
        const :user_id, String
        const :root_id, T.nilable(String)
        const :message, String
        const :create_at, Integer
        const :update_at, Integer
        const :edit_at, Integer, default: 0
        const :delete_at, Integer
        const :props, T::Hash[String, String]
      end
    end
  end
end

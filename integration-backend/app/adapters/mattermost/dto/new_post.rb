# typed: strict
# frozen_string_literal: true

module Adapters
  module Mattermost
    module Dto
      # An empty `root_id` creates a thread root.
      class NewPost < T::Struct
        include Kirei::Domain::ValueObject

        const :channel_id, String
        const :root_id, String
        const :message, String
        const :props, T::Hash[String, String]
      end
    end
  end
end

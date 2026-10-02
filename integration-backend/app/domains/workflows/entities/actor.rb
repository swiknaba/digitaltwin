# typed: strict
# frozen_string_literal: true

module Domains
  module Workflows
    module Entities
      class Actor < T::Struct
        const :user_id, String
        const :channel_id, String
        const :member, T::Boolean
        const :bot, T::Boolean
      end
    end
  end
end

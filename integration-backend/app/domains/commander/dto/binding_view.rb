# typed: strict
# frozen_string_literal: true

module Domains
  module Commander
    module Dto
      # A human's current workflow context in one chat thread.
      class BindingView < T::Struct
        include Kirei::Domain::ValueObject

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

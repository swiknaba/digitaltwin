# typed: strict
# frozen_string_literal: true

module Domains
  module Mattermost
    class WorkerChat
      class Workflow < T::Struct
        const :channel_id, String
        const :thread_id, String
        const :phase, String
        const :saved_phase, T.nilable(String)
        const :archived_at, T.nilable(Time)
      end
    end
  end
end

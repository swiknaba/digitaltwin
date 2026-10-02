# typed: strict
# frozen_string_literal: true

module Domains
  module Jobs
    class Job < T::Struct
      include Kirei::Model

      Payload = T.type_alias { T::Hash[String, Object] }

      const :id, String
      const :kind, String
      const :payload, Payload
      const :dispatch_key, String
      const :status, String, default: "pending"
      const :worker_id, T.nilable(String), default: nil
      const :lease_token, T.nilable(String), default: nil
      const :lease_expires_at, T.nilable(Time), default: nil
      const :attempts, Integer, default: 0
      const :available_at, Time
      const :effect_started_at, T.nilable(Time), default: nil
      const :last_error, T.nilable(String), default: nil
    end
  end
end

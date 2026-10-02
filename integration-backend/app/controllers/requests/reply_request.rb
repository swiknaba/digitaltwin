# typed: strict
# frozen_string_literal: true

module Controllers
  module Requests
    class ReplyRequest < T::Struct
      const :request_id, String
      const :text, String
    end
  end
end

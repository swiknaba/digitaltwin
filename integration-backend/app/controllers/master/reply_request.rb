# typed: strict
# frozen_string_literal: true

module Controllers
  class Master
    class ReplyRequest < T::Struct
      const :request_id, String
      const :text, String
    end
  end
end

# typed: strict
# frozen_string_literal: true

module Adapters
  module Http
    module Dto
      class ReplyRequest < T::Struct
        const :request_id, String
        const :text, String
      end
    end
  end
end

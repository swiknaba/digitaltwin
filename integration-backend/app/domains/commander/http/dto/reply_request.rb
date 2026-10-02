# typed: strict
# frozen_string_literal: true

module Domains
  module Commander
    module Http
      module Dto
        class ReplyRequest < T::Struct
          const :request_id, String
          const :text, String
        end
      end
    end
  end
end

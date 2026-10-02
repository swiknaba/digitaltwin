# typed: strict
# frozen_string_literal: true

module Adapters
  module Herdr
    module Dto
      # Agent CLI kind and arguments for agent.start.
      class LaunchSpec < T::Struct
        include Kirei::Domain::ValueObject

        const :cli, String
        const :launch_args, T::Array[String]
      end
    end
  end
end

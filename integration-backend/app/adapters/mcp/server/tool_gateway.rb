# typed: strict
# frozen_string_literal: true

module Adapters
  module Mcp
    class Server
      module ToolGateway
        extend T::Helpers

        extend T::Sig

        interface!

        sig { abstract.returns(T::Array[Object]) }
        def definitions; end

        sig { abstract.params(name: String, args: T::Hash[String, Object], token: String).returns(Object) }
        def call(name, args, token:); end
      end
    end
  end
end

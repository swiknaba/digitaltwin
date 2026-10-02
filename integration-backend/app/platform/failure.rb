# typed: strict
# frozen_string_literal: true

module Platform
  # Builds the expected-failure payload carried by Kirei::Services::Result.
  class Failure
    extend T::Sig

    sig { params(code: T::Enum, detail: String).returns(T::Array[Kirei::Errors::JsonApiError]) }
    def self.call(code:, detail:)
      [Kirei::Errors::JsonApiError.new(code: code.serialize, detail: detail)]
    end
  end
end

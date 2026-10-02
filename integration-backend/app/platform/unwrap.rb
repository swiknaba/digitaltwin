# typed: strict
# frozen_string_literal: true

module Platform
  # Bridge for callers that still raise on failure: returns the success value
  # or raises Errors::ResultFailed with the first error's detail.
  class Unwrap
    extend T::Sig

    sig do
      type_parameters(:Value)
        .params(result: Kirei::Services::Result[T.all(Object, T.type_parameter(:Value))])
        .returns(T.all(Object, T.type_parameter(:Value)))
    end
    def self.call(result)
      return result.result if result.success?

      error = result.errors.first
      raise Errors::ResultFailed, error&.detail || error&.code || "Result failed"
    end
  end
end

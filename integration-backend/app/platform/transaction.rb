# typed: strict
# frozen_string_literal: true

module Platform
  # Database transaction that spans several models. Kirei transactions are
  # per model, so this uses the raw connection.
  class Transaction
    extend T::Sig

    sig do
      type_parameters(:R)
        .params(blk: T.proc.returns(T.type_parameter(:R)))
        .returns(T.type_parameter(:R))
    end
    def call(&blk)
      Kirei::App.raw_db_connection.transaction(&blk)
    end
  end
end

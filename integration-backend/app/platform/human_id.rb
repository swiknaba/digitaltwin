# typed: strict
# frozen_string_literal: true

module Platform
  # Human ids for tables written through raw Sequel datasets that have no Kirei entity.
  module HumanId
    extend T::Sig

    sig { params(prefix: String).returns(String) }
    def self.call(prefix:)
      Kirei::Model::HumanIdGenerator.call(length: 12, prefix: prefix)
    end
  end
end

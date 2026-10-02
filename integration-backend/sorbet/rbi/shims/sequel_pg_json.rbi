# typed: strict

# Sequel's pg_json extension installs this runtime helper; Tapioca cannot see
# extension methods loaded through Database#extension.
module Sequel
  extend T::Sig

  sig { params(value: Object).returns(Object) }
  def self.pg_jsonb(value); end
end

# The pg_json extension wraps JSONB objects in a delegator rather than a Hash.
# Its explicit conversion is the boundary used by application validation.
module Sequel::Postgres
  class JSONBHash
    extend T::Sig

    sig { returns(T::Hash[String, Object]) }
    def to_hash; end
  end
end

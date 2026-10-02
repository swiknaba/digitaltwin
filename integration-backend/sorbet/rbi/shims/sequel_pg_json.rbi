# typed: strict

# Sequel's pg_json extension installs this runtime helper; Tapioca cannot see
# extension methods loaded through Database#extension.
module Sequel
  extend T::Sig

  sig { params(value: Object).returns(Object) }
  def self.pg_jsonb(value); end
end

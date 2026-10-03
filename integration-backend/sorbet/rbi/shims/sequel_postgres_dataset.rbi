# typed: strict

# The postgres adapter adds this dataset method at runtime; Tapioca does not
# generate adapter-specific dataset methods. Callers pass only these options:
# `target` names the conflict columns, and `update` maps each column to a
# scalar or an SQL expression such as `Sequel.function(:greatest, ...)`.
class Sequel::Dataset
  extend T::Sig

  sig do
    params(
      target: T.any(Symbol, T::Array[Symbol]),
      update: T::Hash[Symbol, T.any(String, Integer, Time, T::Boolean, NilClass, Sequel::SQL::Expression)]
    ).returns(Sequel::Dataset)
  end
  def insert_conflict(target:, update: {}); end
end

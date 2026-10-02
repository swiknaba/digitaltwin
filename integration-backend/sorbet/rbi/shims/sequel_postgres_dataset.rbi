# typed: strict

# The postgres adapter adds this dataset method at runtime; Tapioca does not
# generate adapter-specific dataset methods.
class Sequel::Dataset
  extend T::Sig

  sig { params(opts: T::Hash[Symbol, T.any(Symbol, T::Array[Symbol])]).returns(Sequel::Dataset) }
  def insert_conflict(opts = {}); end
end

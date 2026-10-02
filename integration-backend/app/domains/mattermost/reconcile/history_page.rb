# typed: strict
# frozen_string_literal: true

module Domains
  module Mattermost
    class Reconcile
      class HistoryPage < T::Struct
        const :posts, T::Hash[String, Reconcile::HistoryPost]
        const :order, T::Array[String]
      end
    end
  end
end

# typed: strict
# frozen_string_literal: true

module Domains
  module Messaging
    # Answers whether a user is a proven member of a channel. A failed lookup
    # counts as not proven.
    module MembershipCheck
      extend T::Sig
      extend T::Helpers

      interface!

      sig { abstract.params(channel_id: String, user_id: String).returns(T::Boolean) }
      def member?(channel_id:, user_id:); end
    end
  end
end

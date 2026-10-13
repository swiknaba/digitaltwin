# typed: strict

module TZInfo
  class InvalidTimezoneIdentifier < StandardError; end

  class Timezone
    extend T::Sig

    sig { params(identifier: String).returns(Timezone) }
    def self.get(identifier); end
  end
end

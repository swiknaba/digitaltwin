# typed: strict

module TZInfo
  class InvalidTimezoneIdentifier < StandardError; end

  class Timezone
    extend T::Sig

    sig { params(identifier: String).returns(Timezone) }
    def self.get(identifier); end

    sig { params(local_time: Time).returns(T::Array[TimezonePeriod]) }
    def periods_for_local(local_time); end
  end

  class TimezonePeriod
    extend T::Sig

    sig { returns(Integer) }
    def utc_total_offset; end
  end
end

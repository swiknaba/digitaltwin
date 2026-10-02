# typed: strict
# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe Platform::Failure do
  it "wraps the serialized code and detail in a JSON:API error list" do
    code_class = Class.new(T::Enum) do
      enums do
        const_set(:Missing, new("missing"))
      end
    end
    code = code_class.deserialize("missing")

    errors = described_class.call(code: code, detail: "nothing here")

    expect(errors.map { |error| [error.code, error.detail] }).to eq([["missing", "nothing here"]])
  end
end

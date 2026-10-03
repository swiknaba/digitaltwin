# typed: strict
# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe Domains::Sessions::Operations do
  let(:configuration) { Domains::Workflows::Dto::RoleConfig.new(cli: "pi", provider: "fixture", model: "deterministic", family: "fixture", launch_args: []) }

  it "reserves a valid Herdr name for mixed-case durable IDs without changing the ID" do
    session_id = "session_abCDEF123xyz"
    result = described_class.new.reserve(session_id: session_id, workflow_id: nil, role: Domains::Sessions::Dto::SessionRole::Controller, configuration: configuration, credential_digest: "fixture-digest")
    expect(result.failed?).to eq(false)
    session = Domains::Sessions::Registry.new.find(id: session_id)
    expect(session.id).to eq(session_id)
    expect(session.alias).to match(/\A[a-z][a-z0-9_-]{0,31}\z/)
    expect(session.alias).to eq("digitaltwin-#{Digest::SHA256.hexdigest(session_id).slice(0, 20)}")
  end

  it "preserves existing valid aliases" do
    result = described_class.new.reserve(session_id: "session_first", workflow_id: nil, role: Domains::Sessions::Dto::SessionRole::Controller, configuration: configuration, credential_digest: "fixture-digest")
    expect(result.failed?).to eq(false)
    expect(Domains::Sessions::Registry.new.find(id: "session_first").alias).to eq("digitaltwin-session_first")
  end
end

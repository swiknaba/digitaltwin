require_relative "../spec_helper"
RSpec.describe "Workflow policy preparation" do
  let(:policy) { Domains::Workflows::Policy.new }
  let(:human) { Domains::Messaging::Dto::VerifiedActor.new(user_id: "u", channel_id: "c", member: true, bot: false) }
  let(:bot) { Domains::Messaging::Dto::VerifiedActor.new(user_id: "b", channel_id: "c", member: true, bot: true) }
  it "requires both provider and family diversity" do
    role = ->(provider, family) { Domains::Workflows::Entities::RoleConfig.new(cli: "cli", provider: provider, model: "m", family: family) }
    expect(policy.diverse?(role.call("a", "x"), role.call("b", "y"))).to be(true)
    expect(policy.diverse?(role.call("a", "x"), role.call("a", "y"))).to be(false)
    expect(policy.diverse?(role.call("a", "x"), role.call("b", "x"))).to be(false)
  end
  it "requires exact current reviewer-approved revision and verified humans" do
    expect(policy.human_approval?(actor: human, channel_id: "c", current_commit: "a", reviewed_commit: "a",
                                  verdict: "approve", requested_commit: "a")).to be(true)
    [bot, human].each do |actor|
      expect(policy.human_approval?(actor: actor, channel_id: "c", current_commit: "b", reviewed_commit: "a",
                                    verdict: "approve", requested_commit: "a")).to be(false)
    end
    expect(policy.human_approval?(actor: bot, channel_id: "c", current_commit: "a", reviewed_commit: "a",
                                  verdict: "approve", requested_commit: "a")).to be(false)
  end
  it "never treats unknown/missing/working as settled" do
    %w[unknown missing working].each { |state| expect(policy.settled?(state)).to be(false) }
    %w[idle done].each { |state| expect(policy.settled?(state)).to be(true) }
  end
  it "keeps dispatch closed pending live prerequisite evidence" do
    expect(policy.dispatch_allowed?).to be(false)
  end
end

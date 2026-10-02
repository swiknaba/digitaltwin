# frozen_string_literal: true

require_relative "../../spec_helper"
require_relative "support"

RSpec.describe Domains::Messaging::VerifyHumanSource do
  include MessagingFixtures

  let(:verifier) { double }
  let(:membership) { double(member?: true) }
  let(:service) { described_class.new(verifier: verifier, membership: membership) }
  let(:stored) { verified_delivery(body: "@agent build", revision: 5) }

  before do
    @inbox_id = T.must(Domains::Messaging::RecordDelivery.new.call(delivery: stored).result.inbox_id)
  end

  def refetch(delivery)
    allow(verifier).to receive(:delivery).with(post_id: stored.post_id, channel_id: stored.channel_id,
                                               event_kind: Domains::Messaging::Dto::EventKind::Posted).and_return(delivery)
  end

  def error(result) = result.errors.first

  it "returns the refetched delivery for an unchanged human source" do
    refetch(stored)
    expect(service.call(inbox_id: @inbox_id, destination: "d" * 26).result).to eq(stored)
    expect(membership).to have_received(:member?).with(channel_id: "d" * 26, user_id: stored.actor.user_id)
  end

  it "verify_human_source fails SourceChanged when body or revision differs" do
    [verified_delivery(body: "@agent edited", revision: 5), verified_delivery(body: "@agent build", revision: 6),
     verified_delivery(body: "@agent build", revision: 5, bot: true)].each do |changed|
      refetch(changed)
      failure = error(service.call(inbox_id: @inbox_id))
      expect([failure&.code, failure&.detail]).to eq(["source_changed", "Human source changed"])
    end
  end

  it "fails MissingSource and DestinationMembershipRequired with the former messages" do
    failure = error(service.call(inbox_id: @inbox_id + 1))
    expect([failure&.code, failure&.detail]).to eq(["missing_source", "Missing verified source"])

    refetch(stored)
    allow(membership).to receive(:member?).and_return(false)
    failure = error(service.call(inbox_id: @inbox_id, destination: "d" * 26))
    expect([failure&.code, failure&.detail]).to eq(["destination_membership_required", "Destination membership required"])
  end
end

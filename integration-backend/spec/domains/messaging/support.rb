# frozen_string_literal: true

# Builds messaging DTOs with fixture defaults for the messaging specs.
module MessagingFixtures
  def verified_delivery(post_id: "p" * 26, channel_id: "c" * 26, thread_id: "r" * 26, body: "hello", revision: 1,
                        kind: Domains::Messaging::Dto::EventKind::Posted, user_id: "u" * 26, bot: false, root_post: false)
    actor = Domains::Messaging::Dto::VerifiedActor.new(user_id: user_id, channel_id: channel_id, member: true, bot: bot)
    Domains::Messaging::Dto::VerifiedDelivery.new(channel_id: channel_id, post_id: post_id, thread_id: thread_id, actor: actor, event_kind: kind,
                                                  post_revision: revision, body: body, root_post: root_post)
  end

  def outgoing_message(key: "response", body: "hello", thread_id: "r" * 26, bot: Domains::Messaging::Dto::Bot::Worker,
                       role: Domains::Messaging::Dto::SpeakerRole::Writer)
    Domains::Messaging::Dto::OutgoingMessage.new(channel_id: "c" * 26, thread_id: thread_id, bot: bot, role: role, body: body, key: key)
  end
end

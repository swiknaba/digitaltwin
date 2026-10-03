# Messaging
Owns `inbox`, `outbox`, and `chat_checkpoints`: verified chat deliveries, queued chat messages, and history checkpoints.
Public API: `RecordDelivery#call`, `VerifyHumanSource#call`, `Inbox`, `Outbox`, `Checkpoints`, `Dto::*` and `Errors::*`.
Ports: `DeliveryVerifier` and `MembershipCheck`, implemented by `Adapters::Mattermost`.

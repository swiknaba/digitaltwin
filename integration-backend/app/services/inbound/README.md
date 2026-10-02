# Inbound
Turns Mattermost WebSocket hints and channel history into verified deliveries, then records and classifies them.
Public API: `ChatListener#call` (long-running), `HistoryRecovery#call(channel_id:)`, and `RecordDelivery#call(delivery:)`.

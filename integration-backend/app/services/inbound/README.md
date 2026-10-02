# Inbound
Turns Mattermost WebSocket hints and channel history into verified deliveries for the router.
Public API: `ChatListener#call` (long-running) and `HistoryRecovery#call(channel_id:)`.

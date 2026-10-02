# Outbound
Delivers queued chat messages to Mattermost.
Public API: `DeliverOutbox#call(job:)` for `mattermost.post` jobs and `#reconcile(outbox_id:)` for uncertain results.

# Mattermost adapter
Translates Mattermost API4 JSON into DTOs and verifies inbound deliveries.
Public API: `Api` (posts, channels, users, membership, history, post creation), `DeliveryVerifier`, `Errors::*`, `Dto::*`.
`Client` is the raw HTTP/JSON transport; only `Api` consumes it.

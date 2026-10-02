# Mattermost

This domain owns chat-side state for the Mattermost server: verified delivery identity,
inbox routing, the outbox, and session-bound Worker chat. Transport and REST
verification live in `Adapters::Mattermost`; the listener, history recovery, and
outbox delivery use cases live in `Services::Inbound` and `Services::Outbound`.

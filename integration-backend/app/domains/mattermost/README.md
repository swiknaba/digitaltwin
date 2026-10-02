# Mattermost

This domain is the boundary to the Mattermost chat server. It verifies inbound posts and
membership, records outbound messages in an outbox, delivers them with reconciliation,
and runs the optional listener. It keeps chat transport data and delivery identity checks
out of workflow and controller decisions.

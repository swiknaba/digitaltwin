# Chat Backend

Release configuration and validation for Mattermost Team Edition 11.11.1.
The official compiled core stays byte-for-byte unchanged. Approved minimal
packaging removes all bundled plugins, including Calls and Agents, from the final
filesystem and image layers. No upstream source fork, paid modules, or plugin MCP.

## Why this exists

Mattermost provides real channels/threads, authenticated bot APIs, and our custom
mobile chat/push path without building a chat server. Its database, migrations,
attachments, and release schedule need independent operation from Kirei and the
agent Runtime. We keep the official compiled Team Edition core and remove unused
plugins to avoid adopting Calls or commercially licensed plugin capabilities.
This component can be replaced if another chat platform meets the same verified
thread, bot identity, membership, recovery, and custom mobile/push requirements.

```sh
python3 -m unittest discover -s chat-backend/tests -v
docker build --platform linux/amd64 -t digitaltwin-chat:phase0 chat-backend
# Pull the pinned official AMD64 image first if it is not locally cached:
docker pull --platform linux/amd64 mattermost/mattermost-team-edition:11.11.1@sha256:14a2de6b71fe5f60660fb71ef2f020c5758d8559fdd35a3fca429d301b781154
chat-backend/bin/audit-artifact --derived-image digitaltwin-chat:phase0
chat-backend/bin/local-check --image digitaltwin-chat:phase0
```

Python 3.10+ standard library and Docker are sufficient. Local check uses unique
resource names, private random loopback ports, disposable volumes and public
fixture passwords; it creates no Mattermost account/token and removes its resources.
It tests real startup/native health, REST auth rejection, restart, and empty-server
restore. Leave no live fixtures running. Local image tags are not production pins.

For an operator-provided existing credential and ordinary human thread reply:

```sh
chat-backend/bin/probe-readonly --url https://chat.example.invalid \
  --token-file /outside-repo/private-token-file \
  --channel-id EXISTING_CHANNEL_ID --post-id EXISTING_REPLY_ID \
  --checkpoint-ms EXISTING_MILLISECOND_CHECKPOINT \
  --local-bot-id EXISTING_WORKER_BOT_ID
```

The token file must be private (0600 or stricter); use HTTPS except loopback.
The probe uses GET only, refuses redirects, and emits sanitized checks/counts.
It does not create credentials or save message bodies. It has not been run with
real authenticated credentials in this workstream.

See [release contract and restore/upgrade guidance](CONTRACT.md),
[artifact pins](artifact.lock.json), [artifact audit](evidence/artifact-audit.json),
[live disposable evidence](evidence/local-check.json),
[source findings](evidence/source-contracts.json), and [worker handoff](HANDOFF.md).
Fixtures/tests are source-derived simulations, not authenticated API/event captures.

Root/integrator owns Compose, separate PostgreSQL role wiring, shared contracts,
and cross-service acceptance. Full transitive licensing/dependency audit,
authenticated bot replies/events/reconnect, real attachment restore, signed mobile
push/deep links, and production encrypted restore remain open. Tasks 6-10 keep
required evidence gates; successful packaging/startup does not clear them.

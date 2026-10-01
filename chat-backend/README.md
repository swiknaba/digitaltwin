# Chat Backend

Configuration and release ownership for the official, unmodified Team Edition server artifact.
Own artifact release/digest records, safe configuration examples, compatibility checks, and upgrade guidance here.
Do not import the server repository or implement a chat server.

## API and Configuration Contract

- Kirei integrates with bot accounts through authenticated REST API v4 and WebSocket events.
- Verify channel membership, post/root/channel/user identity, and ordinary thread replies through the selected server release.
- Reconcile event gaps through REST; deduplicate overlapping history and suppress local bot loops.
- Use a separate PostgreSQL database/role and independent upstream migrations.
- Keep attachments and server configuration persistent; coordinate their restore with the database.
- Connect only to the separately hosted upstream push proxy for our mobile push configuration.

The [official API reference](https://docs.mattermost.com/api) is the starting source for release-bound endpoint validation.
Exact event payloads, bot permissions, ports, health checks, and configuration keys need pinned artifact evidence.
Exclude Calls/rtcd and the Agents plugin. Audit the compiled artifact, plugins, dependencies, and notices before release.
Production lifecycle, TLS, routing, persistence, and restart policy remain infrastructure responsibilities.

## Worker Scope

Own Task 1 chat compatibility/provenance and Task 12 upstream upgrade/restore contracts.
Coordinate routing fixtures with Kirei and compatibility pins with mobile-apps and push-service owners.
Propose root Compose changes through the integrator; no production deployment or account creation.

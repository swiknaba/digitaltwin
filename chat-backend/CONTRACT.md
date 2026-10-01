# Release-bound chat contract

The selected release is Team Edition 11.11.1, source commit
`3acb3a7f684d11ccfcec4e5bd11c79f64e3eabf9`. [Source evidence](evidence/source-contracts.json)
records official release source paths/checksums. These findings are source inspection,
not authenticated runtime acceptance. [Fixtures](fixtures/thread-recovery.json) use
synthetic IDs/content and explicitly record that provenance.

## REST and event interfaces for Kirei

| Operation | Official v4 interface | Verification required |
| --- | --- | --- |
| Credential identity | `GET /api/v4/users/me` | Actual authenticated identity |
| Sender identity | `GET /api/v4/users/{user_id}` | ID matches post sender; configured bot IDs always override human classification |
| Membership | `GET /api/v4/channels/{channel_id}/members/{user_id}` | Returned user/channel match; check reader and sender, fail closed on missing/denied membership |
| Post | `GET /api/v4/posts/{post_id}` | Channel, sender, root, timestamps, and deletion state |
| Thread | `GET /api/v4/posts/{root_id}/thread` | Verify root is a top-level post in the same channel; replies carry `root_id` |
| History | `GET /api/v4/channels/{channel_id}/posts?since=<epoch_ms>&collapsedThreads=false` | Recover overlap; deduplicate revisions; never promote checkpoint before durable ingestion |
| Bot reply | `POST /api/v4/posts` with `channel_id`, `root_id`, `message` | Operator-provided bot token and membership; reconcile unknown results before any retry |
| Events | `/api/v4/websocket` authenticated connection | `posted`, `post_edited`, `post_deleted`; event `data.post` is a JSON string |

`model/user.go` serializes `is_bot` with `omitempty`: an authenticated REST user
may omit false. Default that omission to false only after the user has been fetched
by the verified sender ID through authenticated REST; never infer a human from
untrusted event/user claims. `is_bot: true` and configured local/peer bot IDs cannot
approve. Suppress local bot messages; peer bots remain distinct from humans.

Native ordinary replies need no repeated mention. A thread ID is `post.root_id`,
or `post.id` for its top-level root. Verify the root itself rather than trusting
an event's destination. WebSocket sequence is connection state, not durable event
identity. `hello`, authentication, reconnect buffering, and bot permissions still
need real authenticated capture. Kirei owns ingestion/routing; the Python helper
here checks fixtures and probe responses and is not shared production application code.

A durable event key can use channel/post/event kind and revision
`max(create_at, update_at, delete_at)`, with source authenticity checked first.
Store edit/delete kinds separately; duplicate REST/WS revisions must not dispatch twice.
At reconnect, revalidate membership/root/post and fetch an overlapping millisecond
history window. Do not blindly replay deleted/edited approval text.

Channel history uses `page`/`per_page` or `before`/`after` outside the positive
`since` branch. `since=0` falls back to the paginated path; callers must exhaust
pages. Source inspection does not prove completeness/limits of large `since`
responses; validate this with live data before relying on it for recovery.
Thread pagination uses camel-case `perPage`, `fromPost`, `fromCreateAt`,
`fromUpdateAt`, and `direction`. Avoid collapsed-thread filtering when recovering
ordinary replies. The read-only probe fetches a bounded 100-post thread page and
reports failure if the selected reply is outside that page.

`include_deleted=true` is system-admin gated and is not forwarded through the
channel `since` branch in this release. Ordinary bot history cannot be assumed to
recover every deletion after a long disconnect. Retain deletion events and
revalidate known posts; a missing/forbidden post blocks action. Select a verified
reconciliation strategy before clearing authenticated recovery gates.

## Startup and storage proposal for the integrator

Build context `chat-backend/`, `Dockerfile`, platform `linux/amd64`. Root Compose
owns service wiring. The approved derived packaging removes all prepackaged and
installed plugin directories while leaving official core binaries and notices
unchanged. No server source fork or license-check modification is involved.
Build BusyBox exists only in an intermediate stage. `FROM scratch` plus the
filtered filesystem prevents plugin archives remaining in inherited image layers.
The artifact audit scans exported runtime paths and every saved final layer.

- UID/GID `2000:2000`, user `mattermost`, workdir `/mattermost`.
- Start command `/mattermost/bin/mattermost`; HTTP/WebSocket port `8065` only.
- Native health `CMD /mattermost/bin/mmctl system status --local` (30s/10s).
  The artifact has no shell or curl. Keep local mode enabled with the default
  `/var/tmp/mattermost_local.socket`, internal to the container; do not publish it.
- Named writable volumes `/mattermost/config`, `/mattermost/data`, `/mattermost/logs`.
  Use fresh plugin-free volumes. Do not remount old plugin/client-plugin directories.
- `MM_SQLSETTINGS_DRIVERNAME=postgres`; `MM_SQLSETTINGS_DATASOURCE` injected by
  operator/root configuration, using the separate Mattermost database/role.
- `MM_SERVICESETTINGS_SITEURL` must match the actual operator route. Local probe
  uses random loopback ports. Production TLS/routes/restart/backup belong to Infra.
- [phase0.json](config/phase0.json) is a partial config accepted by the server;
  seed it into the writable config volume with UID/GID 2000 before startup.
  Keep plugin enable/uploads/marketplaces/automatic-prepackaged flags false.
  Runtime image ENV also enforces these flags. Never enable plugins to add MCP.
- Bot/account creation and user access tokens are off in the sample. Operator
  provisioning is a separate approved step; existing credentials stay in Kirei.
- Push/email are off in the sample. Push owner/integrator may select the separate
  upstream push proxy URL and compatible mobile identities; do not use hosted
  push as a fallback. No Calls/rtcd port/service or Phase 1 voice configuration.

Image config IDs in evidence identify local builds, not published OCI manifest
digests. Production publication/pinning requires a separate authorized release.

## Restore and upgrade boundary

Stop writes before a coordinated PostgreSQL dump and config/data snapshot.
Back up the independent Mattermost database/role and upstream migration state,
attachments, config, and separately owned push config. Infra owns encryption,
external keys, lifecycle, and production restore. Logs are operational storage;
login/provider state is not included in application backup.

`bin/local-check` restores an empty local schema/config/data snapshot into fresh
containers/volumes, then checks startup and configuration. Its disposable database
role is a fixture superuser and is not the production role contract. Separate
Kirei/Mattermost role isolation remains an integrator/root check.
This check has zero users, posts, and fileinfo rows; it cannot prove message-to-
attachment integrity. An operator test with existing posts/files must verify IDs,
thread relationships, actual downloaded file bytes, bot membership, push, and
reconnect after restoration. Do not mark encrypted production restore accepted.

For upgrades: resolve new official release/digests and licenses; inventory plugins;
rebuild packaging; compare notices/core hashes to that new official artifact;
run component tests/local check and authenticated API/events/recovery plus mobile/
push compatibility. Test rollback on coordinated backups; never assume upstream
schema downgrades work. Keep original volume snapshots until acceptance.

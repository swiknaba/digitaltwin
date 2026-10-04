# Chat worker handoff

Baseline `7889c1a64856d75267ae6030db1743517b6a1342`, branch
`build/chat-backend`, isolated worktree `/tmp/digitaltwin-chat-backend-20261001`.
Only `chat-backend/` changed. User subsequently approved minimal derived packaging
to exclude whole Calls/commercial plugin components and the README rationale.
No main checkout writes, merges, deployment, accounts, or tokens.

## Checks on 2026-10-01

- `python3 -m unittest discover -s chat-backend/tests -v`: 16 pass. Initial
  fixture suite failed before implementation. The source-correct IsBot-omission
  regression also failed before its correction, then the full suite passed.
- `python3 -m py_compile chat-backend/lib/contracts.py chat-backend/bin/audit-artifact chat-backend/bin/local-check chat-backend/bin/probe-readonly`: pass.
- `docker build --platform linux/amd64 -t digitaltwin-chat:phase0-20261001 chat-backend`: pass.
  Build reports constant-platform warnings; AMD64 is the explicitly selected target.
- `chat-backend/bin/audit-artifact --derived-image digitaltwin-chat:phase0-20261001`: pass.
  Official build identity verified; both final saved filesystem layers scanned;
  zero plugin files; official core binaries and all 103 notice/license file hashes
  retained. Full transitive dependency/license review is **open**.
- `chat-backend/bin/local-check --image digitaltwin-chat:phase0-20261001`: pass.
  Real PostgreSQL 18.6 + derived TE 11.11.1, macOS ARM64 Docker Desktop with AMD64
  emulation, random private loopback port, unique resources. Native health, ping
  version, 401 protected REST checks, all plugin flags false, restart, and quiesced
  empty-server DB/config/data restore into fresh volumes passed. Cleanup removed
  all worker containers, networks, and named volumes.
- `git diff --check`: pass.

Evidence JSON distinguishes live unauthenticated results from source inspection
and synthetic fixtures. The local image config ID is recorded; it is not a
published OCI manifest digest. Required compiled MIT license and notices stay in
the image. Source licensing and optional plugin licensing are not conflated.

## Interfaces and integrator proposals

See [CONTRACT.md](CONTRACT.md). Root/shared contracts were not edited.
Root should build the approved minimal `chat-backend/` package; keep AMD64,
non-root UID/GID 2000, native `mmctl system status --local` health and private local
socket, and config/data/logs volumes. Retain the independent Mattermost DB/role
and upstream migrations. Seed partial phase0 config with writable UID2000 config
storage. Never attach old plugin volumes to the derived service.
Do not add Calls/rtcd, plugin/Agents MCP, voice, or hosted push dependencies.

The helper is fixture/probe validation, not a production Kirei adapter. Kirei owns
routing/ingestion. `fixtures/thread-recovery.json` can inform backend tests but is
not an authenticated event capture. Source `IsBot` false can be omitted; positive
`since` does not use `include_deleted`, and include-deleted requests require admin.
Membership, thread/channel identity, overlap revision deduplication, and local-bot
suppression remain mandatory. Missing post/membership must block human actions.

## Unresolved gates and exact requirements

1. Authenticated bot identities/permissions, ordinary human reply events, thread
   reply delivery, WebSocket auth/reconnect, large-history completeness and deletion
   reconciliation: provide an existing approved test server, two configured bot
   credentials and a human test account/channel with memberships, an ordinary
   reply/root, and disposable test data. Credential/account creation needs explicit
   approval. `bin/probe-readonly` can run GET-only checks using an externally stored
   existing token; no credential was available, so that command was not run live.
2. Real attachment/message restore: approved disposable messages/files plus
   authenticated download verification. Empty schema restore does not prove this.
3. Complete artifact dependency/license audit: enumerate compiled dependencies and
   validate every retained notice/OS dependency before release. Core compiled MIT
   identity/hash and complete notice retention are proven; permissibility of every
   dependency has not been established. Removing all plugin archives does not
   establish a clean transitive audit of compiled core/webapp dependencies.
4. Integrator: separate DB-role isolation, root Compose/image build and cross-service
   acceptance; push/mobile owners: own-build push/deep links. Infra: encrypted
   production restore, production image publication/digest and deployment.

Tasks 6-10 retain required authentication/Herdr/idle/Commander MCP gates. This component
work clears neither those gates nor Phase 0 acceptance. Independent integration
review/testing and merge belong to the parent/integrator.

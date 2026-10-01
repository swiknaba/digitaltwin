# Shared Service Boundaries

This is the scaffold agreement, derived from the merged Phase 0 specification and plan.
Behavior below is required. Unselected wire details and live compatibility checks remain open.
The integrator coordinates this file; component workers propose changes before consumers depend on them.

## Agreed Boundaries

| Producer → consumer | Required interface | Source owner |
| --- | --- | --- |
| Mattermost → Kirei listener | Authenticated REST/WebSocket identity; verified channel/post/root/user/membership; durable inbox and reconnect reconciliation | Mattermost validates upstream behavior; Kirei owns ingestion/fixtures |
| Kirei outbox → Mattermost | Bot REST delivery to verified destinations; session role identity; stable deduplication and uncertain-result reconciliation | Kirei |
| Kirei worker → Runtime | Release-bound Herdr Unix-socket API on shared task-local volume; explicit start/prompt/state/stop mapping | Kirei adapter; Runtime captures installed schema |
| Runtime → Kirei | Private session/generation-bound callbacks; server-derived channel/thread/role; idempotency key and exact artifact commit | Kirei client/server source; Runtime packages clients |
| Master CLI → Kirei | Stdio MCP bridge to typed services with verified source context; ordinary workflow gates and destructive-operation confirmations | Kirei |
| Mattermost → push proxy → mobile | Pinned upstream push contract and operator-owned matching app identities/APNs/FCM configuration | Push/mobile owners jointly |
| Applications → PostgreSQL | Independent databases/roles/migrations; jobs, inbox, outbox, audit, and workflow state belong to Kirei | Kirei and upstream Mattermost separately |
| Independent fleets | Verified Mattermost/Git handoffs only; versioned peer envelope; no shared runtime/private APIs | Kirei; `docs/interfaces/peer-handoff.md` in Task 10 |

Kirei's shared `Actor`, `RoleConfig`, `ArtifactRef`, `SessionRef`, and `Outcome` remain the plan's typed entities.
Keep migration order `001_jobs` through `006_confirmations`; the Kirei owner coordinates all additions.
Writer/Reviewer require different providers and model families, verified threads, and exact revision gates.
Uncertain external results remain blocked for reconciliation unless retry idempotency is proven.

## Startup and Configuration Agreement

| Component | Agreed startup/storage behavior | Still to select and record |
| --- | --- | --- |
| Kirei | `bin/web`, `bin/worker`, `bin/chat-listener`; port 3000; UID/GID 10001; `DATABASE_URL`; pool size 5/timeout 2; generated `/livez`, `/readyz`; pending migrations block startup | Complete dependency lock, ENV/secret-file names, callback routes/schemas, actual Linux boot and process health |
| Runtime | UID 10001; `/run/herdr/herdr.sock` mode 0600; foreground `herdr server`; persistent workspace/Herdr/configuration; private terminal | Reviewed image build/context, volume ownership, exact tools/Node pins, private SSH and integrated health |
| Mattermost | Official Team Edition upstream base; separate DB/role; persistent attachments/configuration; native local-mode health | Minimal derived artifact removes excluded plugin archives; artifact/license audit, authenticated API/event fixtures |
| Push proxy | Existing upstream artifact; private port 8066; native config/credential file mounts; `/version` process health | Reviewed config fixture/payload schema and actual provider readiness |
| Mobile | Pinned source and reproducible iOS/Android builds with retained notices | Source revision/toolchains, app IDs, signing/distribution references and push compatibility |

Root local `compose.yml` and `.env.example` now configure PostgreSQL/Mattermost dependencies only.
The opt-in `compose.backend.yml` prepares the backend startup proposal; actual image/startup validation remains required.
See [local integration](local-integration.md) for remaining wiring contracts and the early real roundtrip procedure.
See [foundation validation](foundation-validation.md) for artifact identities and the distinction between preparation and live gates.
Do not use floating image tags or dummy applications to make scaffold startup appear successful.
Production orchestration, networking, TLS, Headscale/Tailscale, encrypted S3 backups, and live deployments remain infrastructure responsibilities.

## Task 1 Evidence and Gates

Official documentation inspected on 2026-10-01 provides starting references, not release-bound runtime evidence.

- [Herdr socket API](https://herdr.dev/docs/socket-api/) documents `herdr api schema --json` from the installed binary.
  Capture its exact schema, version, origin, and checksum before choosing adapter methods.
- [Mattermost API reference](https://docs.mattermost.com/api) defines the API documentation source.
  Validate bot permissions, authenticated events, membership, threads, and reconnect on the selected Team Edition artifact.
- [Push proxy source](https://github.com/mattermost/mattermost-push-proxy) and [mobile source](https://github.com/mattermost/mattermost-mobile) supply protocol/build provenance.
  Validate the selected revisions together; keep upstream voice features outside Phase 0.

| Evidence | Scaffold status | Owner and next action |
| --- | --- | --- |
| Exact Kirei/Herdr/CLI/server/proxy/PostgreSQL/mobile pins and artifact/license audit | Partial; verified upstream identities recorded in the foundation checkpoint; remaining tools and complete artifact audit open | Component owners record verified releases, digests/checksums, licenses/notices |
| Installed Herdr schema and four real CLI start/prompt/state/stop handshakes | Partial; captured schema and preliminary Linux Alpine server/status evidence; four-CLI checks open | Runtime owner delivers reviewed image and sanitized live fixtures |
| Writer settled handshake; unknown cannot mean idle | Open; docs alone cannot prove CLI state semantics | Runtime/Kirei owners validate before sessions/reviews |
| Selected Master CLI real MCP round trip with verified channel context | Open; no live provider session started | Kirei/Runtime owners validate with operator-provided test credentials |
| Authenticated ordinary thread replies, bot identities, membership and REST recovery | Open; dependency health passed, authenticated behavior untested | Mattermost/Kirei owners validate selected artifact locally |
| Disposable mention → queued dispatch → one Herdr CLI → source-thread reply | Open; no running applications or provider test credentials | Integrator proves slice before Tasks 3–5 production workflow work |
| Own signed mobile foreground/background push and thread deep links | Open; enrollment/signing/push credentials/device setup remain human tasks | Mobile/push owners separate offline checks from operator evidence |

Tasks 6–10 retain the plan's blocking gates for missing required Herdr, idle, authenticated chat/thread, or selected Master MCP evidence.
Preparing a Dockerfile, build recipe, fixtures, or offline component tests does not clear these gates.
No production infrastructure, provider login, app-store submission, or signed-device delivery has occurred in this scaffold task.

## Worker Handoff Rules

1. Start each component worktree from the same integrated scaffold commit.
2. Limit writes to the assigned folder; request root/shared-contract edits from the integrator.
3. Agree on callback wire schemas, secret references, socket permissions, and startup details before implementing consumers.
4. Report changed files, commit, checks, exact pins, and evidence gaps.
5. Merge prerequisite commits before dependent code; run integration after merging compatible component work.

Kirei owns callback/MCP client source. Runtime includes it through a documented build context or versioned build artifact.
Do not duplicate those clients between folders or invent a second shared application package.
The integrator owns cross-service fixtures in `tests/`; Kirei owns its unit/domain/adapter fixtures.

Root `tests/` runs automated integration checks. It does not grant authorization for live production or provider/device setup.
Successful local checks cannot substitute for the plan's live and operator acceptance rows.

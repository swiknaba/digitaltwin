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
| Commander CLI → Kirei | Stdio MCP bridge to typed services with verified source context; ordinary workflow gates and destructive-operation confirmations | Kirei |
| Mattermost → push proxy → mobile | Pinned upstream push contract and operator-owned matching app identities/APNs/FCM configuration | Push/mobile owners jointly |
| Applications → PostgreSQL | Independent databases/roles/migrations; jobs, inbox, outbox, audit, and workflow state belong to Kirei | Kirei and upstream Mattermost separately |
| Independent fleets | Verified Mattermost/Git handoffs only; versioned peer envelope; no shared runtime/private APIs | Kirei; `docs/interfaces/peer-handoff.md` in Task 10 |

Kirei's shared `Actor`, `RoleConfig`, `ArtifactRef`, `SessionRef`, and `Outcome` remain the plan's typed entities.
Keep existing migration order `001_jobs` through `006_confirmations`; append `007_commander_routing` for contextual bindings/follow-ups and `008_workflow_lifecycle` for durable lifecycle/request receipts. The Kirei owner coordinates all additions.
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

Root local `compose.yml` and `.env.example` configure the reviewed PostgreSQL/chat/backend/Runtime core with migration and volume gates.
Chat uses the review-cleared minimal derived artifact and writable seeded config; plugins/email/push remain disabled.
The independently tested overlay graph is promoted into default Compose; the old overlay paths are compatibility no-ops.
The promotion requires its own independent default-entrypoint rerun. Listener and push remain opt-in, with explicit operator credentials.
See [local integration](local-integration.md) for remaining wiring contracts and the early real roundtrip procedure.
See [foundation validation](foundation-validation.md) for artifact identities and the distinction between preparation and live gates.
Use explicit upstream release tags (major/minor is sufficient when published); do not use `latest` or dummy applications to make scaffold startup appear successful.
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
| Selected Commander CLI real MCP round trip with verified channel context | Open; no live provider session started | Kirei/Runtime owners validate with operator-provided test credentials |
| Authenticated ordinary thread replies, bot identities, membership and REST recovery | Open; dependency health passed, authenticated behavior untested | Mattermost/Kirei owners validate selected artifact locally |
| Disposable mention → queued dispatch → one Herdr CLI → source-thread reply | Open; no running applications or provider test credentials | Integrator proves slice before Tasks 3-5 production workflow work |
| Own signed mobile foreground/background push and thread deep links | Open; enrollment/signing/push credentials/device setup remain human tasks | Mobile/push owners separate offline checks from operator evidence |

Tasks 6-10 retain the plan's blocking gates for missing required Herdr, idle, authenticated chat/thread, or selected Commander MCP evidence.
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

## Commander routing wire contract

The standalone `digitaltwin-mcp` stdio bridge reads the current request token from a runtime
file and calls private `/internal/commander/{manifest,tools}` HTTP endpoints. Only a live Commander
request capability may invoke tools. Tool arguments contain no actor, role configuration or
session creation authority. Kirei re-fetches the source human and destination memberships.
`send_prompt` cites 1-10 recent accessible inbox IDs grounded in the target thread, source task
or recorded binding. Conflicts ask for clarification. `workflow_control` queues the exact
source/workflow/version for worker validation; approval still requires exact human Git binding.

`digitaltwin artifact-ready` and `review-ready` POST session-capability generation/commit callbacks.
HTTP only authenticates and queues `review.callback`; the socket/worktree-owning worker checks
actual settled state and Git evidence. Review transitions enqueue `review.release` transactionally.
Deleted/revoked sources remain audited for reconciliation; transient server failures retain queue order for retry. Session renewal verifies the same conversation and file digest;
terminal transitions durably queue both role stops before archival.

Operator acceptance needs trusted `ROLE_CONFIG_FILE` profiles (`commander`, `writer`, `reviewer`:
cli/provider/model/family/launch_args), current bot/token file references, verified project mapping
and repository origin. Supply these through a private operator overlay to web, listener and worker
as needed; mount no provider state into Git/images. Only the worker mounts `/workspace` and
`/run/herdr`; web has neither. Runtime packages backend-owned clients from a checksum manifest.
No environment variable enables `dispatch_allowed?`; live evidence and reviewed policy code are
still required. Gemini remains the specified Commander CLI; its actual launch/MCP profile is unproved.

Bounded recovery commands and the minimum operator setup/evidence are recorded in
[Commander routing setup](commander-routing-setup.md). Human follow-up outcome confirmation is explicitly
audited and never treated as an automatic socket acknowledgment. Thread/session receipt recovery
requires authoritative remote evidence and does not repeat an uncertain external action.

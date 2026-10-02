# Backend worker handoff — 2026-10-01

Initial component baseline: `7889c1a64856d75267ae6030db1743517b6a1342`; merged branch `build/integration-backend`.
Clean-migration correction baseline: `0c79c77719713ca38417d5ea6da63ca6bc0fa401`; branch `fix/backend-clean-migration`.
Only `integration-backend/` changed. No shared checkout switching, root edits, production access, provider login, or paid calls.

## Delivered and checked

- Ruby 4.0.7 digest-pinned Alpine image; Linux AMD64 and ARM64 builds.
- Falcon 0.57.0 actual HTTP startup, concurrent requests, generated health routes, private callbacks, and bounded input.
- Kirei 0.10.0 request-local router handling with fiber/thread overlap and exception cleanup tests.
- Global Sequel fiber concurrency, exclusive PostgreSQL transactions, bounded exhaustion, rollback and exception cleanup.
- Six contiguous migrations; actual migration down-to-zero/up-to-six succeeds.
- Durable jobs with unique keys, 30-second leases, 10-second heartbeat, five attempts, bounded backoff, stale-token checks, and uncertain-effect blocking.
- Atomic outbox/inbox state, verified identity/thread routing, paused/review message queues, source-derived REST/WS adapters and recovery checkpoints.
- Outbox delivery verifies authenticated bot identity and source thread; lost outcomes require verified reconciliation and never blind resend.
- Safe enrollment mapping and independent Git worktrees with real local Git tests; no GitHub resources created.
- Session-bound `say` callbacks: derived destination/role, credential digest/generation/expiry checks, active phase, replay/body checks.
- Pure diversity, exact revision approval, and settled-state policy; live workflow/session dispatch remains closed.

`bin/check` passed on Ruby 4.0.7 `x86_64-linux-musl` under Docker Desktop AMD64 emulation:
62 component examples, 4 separate real-PostgreSQL migration-helper examples, 1 real application clean-migration subprocess example, 58 files through Layout/Lint/Security, and strict shared-entity static typing.
PostgreSQL: pinned `18.6-alpine`, unique disposable network/database/container; no other worker containers touched.
The actual ARM64 non-root web and worker roles started and passed their own health commands.
The actual Falcon network test also ran inside the AMD64 component suite.
Native `liburing` was added after the first image exposed a missing event-selector library.
Ruby's upstream IO::Buffer experimental warning remains visible; it does not fail the checks.

## Independent review corrections

History recovery quarantines permanently rejected items (including local bot posts and malformed/forged entries) in an idempotent audit record. Transient fetch failures leave the channel checkpoint unchanged and reprocessing remains inbox/job-idempotent.
The pinned positive-since SQL caps unordered results at 1000: a response at that cap fails closed before processing or checkpoint advancement, with an operator recovery error. A 1010-post synthetic backlog returning the upstream 1000-post cap is covered; no complete large-backlog recovery is claimed.
Checkpoints use accepted history-snapshot revisions, never later per-post REST refetch revisions. A concurrent edit/refetch and missed intervening post/reconnect regression passes.
These are offline transport regressions on real PostgreSQL, not authenticated reconnect evidence. Frozen callback bytes are unchanged.

## Clean migration correction

Independent combined boot found that the actual rake migration connection bypassed the app pool's PostgreSQL JSON extension setup. Migration 004 therefore failed on `Sequel.pg_jsonb` from a fresh database, despite passing the preloaded component harness. Both migrate and rollback connections now explicitly load `pg_json` and `pg_array` before applying migration files.
A standalone regression uses no app/spec-helper preload and spawns the real `bundle exec rake` commands against an empty disposable PostgreSQL database: migrate zero to six, repeated migrate, rollback six to zero, and migrate zero to six again.
Fresh Linux AMD64 image `digitaltwin-backend-clean-fix:20261001` (local only) ran its real `bundle exec rake db:migrate` from an empty database through version six; its web and worker roles then passed their actual health commands as UID/GID10001. Full component checks passed again. No Compose shim or frozen callback modification was used.

## Typing evidence

`bundle exec spoom srb tc` fails; it is not a completion pass.
With identical current locked dependencies, the exact scaffold source produces 104 errors: 98 dependency-gem RBI errors and 6 framework-source errors.
The initial implementation at `81d5d5c` produces 150 errors: the same 98 dependency-gem RBI errors and 52 backend-source errors.
The 46 additional diagnostics reference unresolved Sequel/Async/Protocol/Kirei constants or inherited framework methods/classes.
No errors were suppressed or removed from the whole-project configuration.
`bin/typecheck-contracts` directly checks the strict shared entities and verified-delivery contract and passes.
Generate and validate complete framework/dependency RBIs before claiming whole-project type coverage.
The lint claim covers Layout/Lint/Security only, not every default style/metrics preference.

## Packaging and integration agreement

- Build context: `integration-backend/`; same image runs `bin/web`, `bin/worker`, `bin/chat-listener`.
- UID/GID `10001:10001`; web port 3000; required `DATABASE_URL`; migrate before every role starts.
- Health: role-specific `bin/health <role>`; override the default web Docker probe for worker/listener in Compose.
- Runtime owns `/run/herdr/herdr.sock` (0600, shared UID10001). No socket adapter methods were fabricated.
- Runtime callback v1: only `integration-backend/bin/digitaltwin`, Ruby >=3.1 standard libraries, no bundle/DB dependencies.
- Frozen callback SHA256: `cd7dd6f80e050b91387c92fa285964f19ed089bb84b44c8dbb0dd5caf8478054`.
- Private `POST /internal/callbacks/say`: Bearer session credential; JSON generation/key/text only; success 202.
- Runtime receives file references/environment, never Mattermost credentials. No live credentials are minted by this foundation.
- `CHAT_VALIDATION_MODE=1` permits disposable Mattermost listener/outbox checks only. Every workflow/Master job remains blocked.
- Root Compose/env/contracts and root acceptance tests remain integrator-owned; proposed ENV/health contract is in README.

## Open evidence and implementation

The Mattermost shapes were independently implemented from release-source evidence at commit `3acb3a7f684d11ccfcec4e5bd11c79f64e3eabf9`.
Offline fixtures and local TCP tests do not establish authenticated Mattermost transport, live permission behavior, WS reconnect, or deletion recovery.
`is_bot:false` may be omitted in authenticated REST; configured local/peer IDs still cannot authorize human actions.
Ordinary bot history cannot guarantee tombstones: admin-only deleted-post behavior and the `since` path need an explicit recovery decision.
Live deletion visibility and channel-discovery/backfill completeness remain acceptance work.

Required operator input: disposable listener/bot accounts and their mounted token files; verified bot/channel IDs and memberships; authorized provider test access.
Prove the real mention → queued dispatch → Herdr CLI → source-thread reply slice before enabling production Tasks 3-5.
Tasks 6-10 still require authenticated chat/thread evidence, four CLI prompt/state/stop contracts, Writer settled, and selected Master MCP round trip.
Sessions, review coordinator, state transitions/approvals, Master MCP, artifact/review callbacks, PR delivery, peer and memory flows remain unimplemented behind those gates.
Prepared tables and pure policy checks do not clear those gates.
GitHub private creation requires operator-supplied `gh` and authentication; neither is installed/validated in this image.
No signed mobile push, full Phase 0 acceptance, published OCI artifact, or production deployment is claimed.

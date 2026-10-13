# OpenCode-first Commander reset implementation plan

**Status:** The approved maintained UI patch is implemented as a pinned source
artifact; it is not yet built or live-verified, and Gate 1 remains incomplete. This
plan authorizes no provider login, deployment, credential creation, or firewall
change.

**Source of truth:** [Commander product specification](../../commander-feature-spec.md)
at `9575ff1` (`main` on 2026-10-12). The earlier Phase 0 and Commander/Hermes
plans are historical where they conflict with this document.

## Goal

Refocus Digitaltwin into a thin, optional Commander extension for OpenCode. OpenCode
owns project chats, remote workspaces, agents, and Git feedback. Kirei owns only
durable future commitments. There is no Mattermost path, no Digitaltwin mobile app,
and no Kirei workflow approval/review gate on ordinary OpenCode work.

## Current evidence and first decision

- The installed desktop bundle's CLI reports `OpenCode v2.0.27`; it runs against the
  existing local service. Its public OpenAPI proves session create/prompt/log/steer/
  interrupt and pairing controls, sufficient for a bridge's runtime mechanics.
- A repository-local global plugin probe was installed through one retained symlink.
  The actual release reports it active with only `features.server: true`; it exposes
  no UI/client/session/capability feature. The plugin's required default-definition
  contract also differs from current published documentation. Release-bound details,
  retained-plugin instructions, and the failed Gate 1 criteria are in
  [OpenCode Commander Gate 1 evidence](../../interfaces/opencode-commander-gate.md).
- Claude Code `2.1.267` is authenticated through its existing account. A direct
  read-only invocation with `--model opus --effort medium` resolved to canonical
  `claude-opus-5-5`; its review findings are incorporated below.

**Gate 1 failed and remains a hard stop.** Before building a Commander bridge, a
future-task API, or learning integration, prove on the maintained *pinned* OpenCode build that a
supported extension point can: (a) add an always-visible global Commander control,
(b) open the same durable Commander conversation without destroying the active
project session, (c) render streamed external runtime responses, and (d) obtain a
trusted user-and-conversation-bound bridge capability without a static credential in
project configuration. DOM injection is prohibited. If the supported surface cannot
do this, stop and choose either an
upstream contribution or a narrowly maintained OpenCode UI patch; do not build an
unsupported bridge around it.

The selected path is the maintainable source patch at
[`commander/opencode-ui-patch`](../../../commander/opencode-ui-patch/), not arbitrary
extension installation or renderer DOM injection. It adds only the typed global
control and session side-panel shell. A greenfield bridge must still implement the
durable Commander conversation, streaming/reconnect, and trusted capability contract
before this gate can pass.

Only after Gate 1 and the disposable direct-OpenCode slice (project Git work,
cancellation, restart, and chosen remote-web/pairing access) pass may Mattermost
and the old Kirei workflow architecture be removed. This ordering comes directly
from the source specification and prevents an unsupported UI integration from leaving
no usable product path.

## Scope and explicit non-goals

In scope after the gates: one Commander conversation, global operator-owned OpenCode
addition, a thin Commander-runtime bridge, Kirei one-time future tasks, shared agent
scheduling tooling and instruction, compact learning visibility, and documentation
for setup/disable/recovery.

Out of scope: Mattermost migration or transcript export, chat/mobile/push replacement,
Kirei project-chat interception, recurrence before one-time recovery is proven,
automatic project work/merge/deploy from a schedule, Obsidian, or deployment and
credential provisioning.

## Design decisions to confirm during Gate 1

1. **OpenCode UI contract.** Record the exact OpenCode release/checksum, plugin
   SDK/version, extension API, and a sanitized reproduction. A global tool alone is
   insufficient because it does not meet the visible-control/conversation-surface
   requirement.
2. **Bridge boundary.** A persistent, operator-run `commander-bridge` service—not
   a browser tab or global plugin—owns the stable Commander conversation ID, runtime
   profile, delivery receipt store, and Kirei private-service identity. It maps
   OpenCode actions to start/reload, prompt/stream, steer, cancel, and final-result
   operations. A due check-in is first accepted and durably deduplicated by this
   bridge even when no OpenCode UI is connected; the bridge appends/replays it to the
   same Commander conversation when the supported OpenCode surface is available.
   A successful UI append is acknowledged by `delivery_key`; after an accepted but
   unrecorded bridge result Kirei marks the execution `uncertain` and an owner must
   query/reconcile the exact key rather than resend it.
3. **Runtime choice.** Hermes remains only an initial candidate. Select it only
   after a no-provider local lifecycle probe demonstrates the required operations;
   do not expose its name in the UI or make it a permanent public contract.
4. **Kirei boundary.** `FutureTasks` is its own typed domain and durable record.
   OpenCode custom tool and MCP are thin adapters over the same service; neither can
   write jobs directly. Ordinary OpenCode sessions must run if Kirei is stopped.
5. **Scheduling safety.** Separate mutable task state from an immutable execution
   attempt. Version each task, use a unique due-execution key, lease the queued
   operation, and persist `running`, `awaiting_disposition`, `completed`, `failed`,
   or `uncertain` before/after each external delivery. A due task only posts a
   Commander check-in; it never starts project work itself.
6. **Learning visibility.** Bridge events are compact and reveal `memory` or `skill`
   plus a summary, never transcript text. Initial configuration explicitly chooses
   automatic-memory and staged-skill policies before runtime learning is enabled.
7. **Trust model.** Gate 1 must prove an OpenCode-supported way for the global
   extension to obtain a short-lived, user-and-conversation-bound bridge capability
   without putting a static Kirei/runtime credential in project configuration. The
   bridge exchanges that capability for its private Kirei identity. It issues,
   rotates, revokes, and records one-time capability identifiers; Kirei verifies
   audience, actor, Commander conversation, expiry, and replay before every API
   call. A project or tool never supplies its own actor, origin, target, outcome, or
   durable service credential. Because project code sharing the same OS user can be
   hostile, file placement alone is not a security boundary; lack of a supported
   trusted-extension/session proof fails Gate 1.

## Future-task state and delivery contract

### Domain records

`FutureTask` is the mutable user commitment: immutable `id`, authenticated `actor`,
server-derived `origin`, Commander-only `target` for v1, bounded text/references,
original IANA timezone/local request, canonical UTC `due_at`, `version`, and state.
It starts `scheduled`; a due claim moves it to `running`; a persisted bridge receipt
moves it to `awaiting_disposition`. It becomes `completed` only after the
user/Commander disposition is durably recorded, `failed` after a reconciled terminal
execution failure, `canceled` either before execution starts or by the
capability-verified post-delivery `user_canceled` disposition or the owner-only
unrecoverable-effect resolution, or `uncertain` after an unreconciled external effect.
A late receipt/reconciliation transitions
`uncertain` to `awaiting_disposition` or `failed`. Rescheduling updates one task with
the exact `expected_version`, increments `version`, and creates one new schedule
generation: before delivery it is the normal update operation; after delivery it is
the capability-verified `rescheduled` disposition and carries a newly validated
`due_at`, IANA zone, and local time. A `failed` task is final; the actor can create a
new task deliberately but cannot reschedule the failed record. No v1 operation
targets a project session.

`FutureTaskExecution` is the mutable schedule-generation record: `id`, task id, task
version/generation, unique `delivery_key`, job reference, bridge receipt, timestamps,
and state (`queued`, `claimed`, `delivering`, `delivered`, `failed`, `uncertain`, or
`stale`). Uniqueness on task plus generation prevents a second external check-in.
Each worker/bridge interaction adds an immutable `DeliveryAttempt` record with its
sequence, effect-boundary timestamp, result/receipt or safe failure detail. The queue's
`complete`, `blocked`, and `uncertain` are infrastructure statuses only; the public
API exposes the domain state, retained attempts, and typed outcome.

### Atomic transitions

- Create requires an actor-scoped idempotency key. Same key/body returns the original
  task; the same key with different normalized content returns a typed conflict.
  Kirei transactionally creates task, generation, execution, and queued job.
- Update/cancel require the task id and `expected_version`; a row/advisory lock and
  conditional state/version update make update-versus-claim atomic. A cancelled or
  superseded job conditionally records `stale` and performs no bridge I/O.
- The worker claims only a current `queued` execution. Immediately before bridge I/O
  it marks `delivering`, calls `lease.begin_effect`, and passes the immutable
  `delivery_key`. A bridge timeout/lost result after that point is `uncertain`; a
  reconciliation job retries the same idempotency key after a bounded delay. A
  duplicate returns the original receipt, while a request that never reached the
  bridge is delivered once. An unreachable bridge remains `uncertain` for owner
  recovery; the worker never invents a second key. A receipt is persisted before the
  job completes.
- Reconciliation records either `delivered` (and task `awaiting_disposition`) or
  `failed` (and task `failed`) under the task lock. The regular cancel/update API
  applies only before a task starts. After a delivered check-in, a separate
  capability-verified
  `record_disposition` transition holds the task lock and requires the exact task
  version plus an actor-scoped disposition idempotency key. It records one immutable
  outcome: `assessed` or `project_work_requested` marks the original task
  `completed`; `user_canceled` marks it `canceled`; `rescheduled` marks it
  `scheduled`, increments its version, and transactionally creates the next schedule
  generation/execution on that same task ID. A disposition is rejected until its
  exact execution has a persisted delivery receipt; duplicate same-body dispositions
  return the saved outcome and changed/out-of-order ones conflict. `project_work_requested` is a
  visible user decision reference only: it cannot itself start project work.
- After the bounded automatic reconcile period, an owner-only, capability-verified
  `resolve_uncertain` operation requires the task's exact version and a resolution
  idempotency key. It may query/retry only the existing delivery key; it records
  `awaiting_disposition` for a receipt, `failed` for a terminal bridge failure, or
  `canceled` with an immutable operator reason when the external effect remains
  unknowable. A late bridge receipt is retained as an immutable attempt/audit event
  but never reopens that canceled task. The operation may never create a new delivery
  key or a second check-in.
- Retry exhaustion that never crossed the effect boundary produces a visible domain
  `failed`, not an opaque queue-only `blocked` state. The first release supports
  one-time dates only. Store canonical UTC plus original IANA zone/local time; reject
  invalid zones, DST gaps, ambiguous folds without an explicit offset, past times,
  and mismatched local offset/zone requests.

## Greenfield cutover policy

The user has confirmed that nothing is live and has rejected legacy-compatibility
burden. At the approved deletion milestone, replace the current `001`–`010`
Mattermost/workflow schema history with one clean FutureTasks baseline plus only
retained platform tables. Do **not** append a destructive compatibility migration,
ship retired tables to new installs, export/migrate chat data, or promise rollback
across this architectural reset. Git retains historical migrations. The cutover
commit must update empty-database migration tests, bootstrap/CI fixtures, and the
documented local reset procedure; it may not target a user database.

## Acceptance scenarios

### Gate 1: supported OpenCode surface

- Fresh OpenCode launch loads an operator-global addition; a project-local
  `opencode.json` cannot replace it or access Commander credentials.
- The visible Commander control is present from a project screen, opens branded
  Commander, and preserves the original project session unchanged.
- Refresh/restart restores the same Commander conversation identity and reconnects
  streaming without duplicate messages.
- A deliberate cancellation/steer reaches exactly the active Commander operation;
  stale or different-conversation capabilities are rejected.

### Gate 2: direct OpenCode baseline

- A disposable remote repository is edited through a direct OpenCode project session;
  change, cancellation, restart, and Git recovery are visible in OpenCode/Git without
  Kirei availability.
- The selected authenticated remote-web or pairing path works from desktop and the
  intended mobile browser path. Treat credentials/device access as operator evidence,
  never a repository fixture.

### Future-task service

- Commander MCP and the global OpenCode tool create the same one-time task shape and
  receive a returned task ID before claiming success.
- List/read return only tasks visible to the authenticated actor; project context is
  a navigation hint, never an authority grant. Update and cancel reject a running,
  finished, foreign, stale-version, or changed-idempotency-key task without creating
  another job.
- UTC conversion preserves the submitted IANA timezone and local display value.
  Invalid zones, past dates, DST gaps, ambiguous folds without an explicit offset,
  and mismatched offsets fail with typed validation errors.
- Same actor/idempotency key and same normalized create body returns one task;
  the same key with a changed body conflicts. Concurrent update-versus-claim and
  cancel-versus-claim leave at most one current execution; stale jobs make no bridge
  call.
- A delivered task becomes `awaiting_disposition` and accepts exactly one disposition:
  assessed, user-canceled, rescheduled on the same task ID with a new generation, or
  a recorded project-work request. Duplicate
  dispositions return the first recorded outcome; changed or out-of-order retries
  conflict, and no disposition can itself launch project work.
- A due task is delivered once to Commander after worker restart. A crash before
  delivery is retried through the same execution record; a crash after an unknown
  bridge result becomes `uncertain` and is reconciled by retrying its exact delivery
  key, never by blind/new-key resend. An unreachable bridge remains explicitly
  uncertain for owner recovery.
- An owner resolves an `uncertain` task only through the exact-version,
  capability-verified path: a recovered receipt yields `awaiting_disposition`, a
  terminal bridge failure yields `failed`, and a final unrecoverable effect can be
  canceled with a recorded reason. A failed task cannot be rescheduled; creating a
  new task is explicit.
- If the OpenCode UI is disconnected, the bridge records one pending visible
  Commander item. Restart/reconnect produces it once. An unavailable Kirei makes
  direct project work continue normally and returns an explicit scheduling failure;
  it never creates a local agent scheduler.
- A due task shows its origin, project/repository references, scheduled timezone,
  attempt, and outcome. It never revives its originating project session.

### Commander learning and recovery

- Runtime memory/skill acceptance or staging produces one compact Commander item;
  it does not expose transcript content nor confer scheduling/project authority.
- Repeated stream events, tool callbacks, or worker retries do not duplicate a
  Commander message, task execution, or learning notice.
- Forged actor/origin/outcome fields, replayed/expired/revoked/cross-user or
  cross-conversation capabilities, and a project-local config attempting to replace
  the global addition all fail before task mutation or bridge delivery.

### Deletion/regression

- After Gates 1 and 2 and FutureTasks acceptance, default startup contains no Mattermost, push, mobile, chat listener,
  Mattermost environment variables, or chat-only database role. No historical chat
  data is migrated.
- The remaining Kirei runtime accepts only future-task operations and worker jobs;
  it has no ordinary prompt, transcript, approval, review, project-workflow, or
  Mattermost adapter endpoint.
- Repository docs, runbooks, acceptance scripts, and CI describe the OpenCode-first
  system and accurately distinguish simulated checks from operator/live evidence.

## Incremental implementation map

### 0. Baseline and Gate 1 spike (no product bridge)

- Add `docs/interfaces/opencode-commander-gate.md` with exact version/pin, globally
  loaded plugin experiment, supported API evidence, trusted-extension/capability
  result, deterministic pass/fail criteria, and the next owner/action if it fails.
  Screenshots are supporting evidence, not the contract.
- Add a disposable, operator-run smoke harness under `tests/opencode/` that validates
  the selected supported API without reading credentials or depending on DOM selectors.
- Record the direct-OpenCode Gate 2 manual/automated matrix separately. Do not change
  production code or remove current paths in this step.

### 1. Thin global OpenCode integration (only after Gate 1)

- Create a versioned, repository-owned TypeScript package and its lockfile/check
  command; installation puts its reviewed build in operator-global OpenCode
  configuration, never project checkout configuration. Its stable public interface
  is a branded Commander control plus a typed bridge client; runtime/harness naming
  stays internal.
- Model `CommanderConversationId`, command/cancel/steer request, streaming event,
  bridge capability, and delivery receipt as explicit TypeScript values. The bridge
  persists conversation mapping/delivery idempotency; the extension holds no durable
  Kirei/runtime credential. The authorized isolated core now lives in
  `commander/bridge/`; it has no runtime/Kirei/OpenCode wiring and does not clear a
  Gate 1 requirement.
- Add component tests for session preservation, reconnect, stale capability rejection,
  stream ordering/deduplication, and cancellation races.

### 2. Commander runtime adapter (only after the direct-OpenCode slice)

- Package the selected runtime behind an adapter with typed start, prompt, stream,
  steer, cancel, collect, and recover outcomes. Keep operator credentials and runtime
  profile outside Git/images; mount only a per-Commander profile.
- Add a generic learning-event adapter and visible compact notice path. Include a
  runtime-no-op test double for deterministic bridge tests.

### 3. Kirei future-task bounded context

- Introduce a strict `Domains::FutureTasks` bounded context with one concrete Ruby
  class per file: typed task/execution DTOs/entities/errors and public services. Its
  models own the clean baseline tables described above; HTTP/MCP/OpenCode are adapters
  and public services return `Kirei::Services::Result`.
- Use existing typed job/transaction/lock primitives to create an idempotent due
  execution. Define precise result variants for validation, conflict, unavailable,
  stale-version, delivered, failed, and uncertain states; controllers/adapters stay
  thin. Kirei's bridge client accepts only the bridge private identity and delivery
  key; it cannot create a project workflow.
- Implement typed HTTP/private bridge API, MCP adapter, and OpenCode global-tool
  adapter over one service. Require capability audience/actor/conversation/expiry/
  nonce verification, bounded input, `expected_version` for mutation, and paginated
  `(created_at, id)` list order. Add a `future-work` skill plus a concise
  discoverability instruction that requires a returned ID.
- Unit/integration tests cover timezone validation, idempotent create, concurrent
  update/cancel/due claims, retries, crash points, authorization, and restart recovery.

### 4. Controlled architectural deletion

- Once Gates 1 and 2 and the new bounded-context acceptance pass, remove
  `chat-backend/`, `push-service/`, `mobile-apps/`, Mattermost-oriented runtime
  provisioning, chat listener/outbox/inbox/adapters, workflow/review/approval
  domains, and the corresponding Compose services/tests/docs.
- Simplify root Compose to Kirei/PostgreSQL only when Kirei remains necessary, and
  keep OpenCode operator installation separate. Replace legacy root acceptance tests
  with future-task and OpenCode integration contract checks.
- Preserve historical artifacts only where Git history suffices. Do not create a
  compatibility server or migrate chats merely to preserve the retired architecture.

### 4a. Exact retained/replaced/deleted inventory

Perform the cutover in dependency order and review this inventory against the tree
before every deletion commit:

| Area | Retain or replace | Delete at cutover |
| --- | --- | --- |
| `integration-backend/app/platform/` | Retain typed transaction, lock, audit and job primitives; add FutureTasks job kinds/handlers | No platform code that encodes chat delivery assumptions |
| Domains/services | Replace composition and public services with FutureTasks and bridge-delivery services | `Messaging`, `Workflows`, `Reviews`, legacy `Commander` routing, `Sessions` lifecycle, Git approval/orchestration services |
| Adapters/routes/binaries | Replace with private bridge API plus narrow MCP API | Mattermost HTTP/WS, chat listener, callback clients, legacy MCP/tools, `bin/chat-listener`, workflow/Commander recovery commands |
| Runtime | Retain only the selected Commander bridge/runtime topology and explicit profile storage | Herdr and multi-CLI provisioning not needed by the selected adapter; Mattermost callback/client plumbing |
| Root services/config | Keep Kirei/PostgreSQL only if FutureTasks needs them; keep operator OpenCode installation outside Compose | `chat-backend/`, `push-service/`, `mobile-apps/`, Mattermost role/database, chat volumes/profiles/env/init scripts |
| Tests/CI/docs | Replace with OpenCode gate/bridge/FutureTasks tests and clean-schema CI | Mattermost full-stack fixtures, chat contract/evidence, obsolete runbooks and live-chat claims |

The final cutover test scans live source/configuration (excluding Git history and
explicitly historical documents) for retired imports, environment variables, route
mounts, Docker services, and job kinds; Zeitwerk/default boot and the new worker must
pass without chat activation.

### 5. Operational documentation and final validation

- Rewrite root/component READMEs, layout/service-boundary documents, `.env.example`,
  runbooks, and planning index to state the new product/authority boundaries.
- Run focused TypeScript and Ruby checks plus full backend `bundle exec spoom srb tc`,
  RuboCop, RSpec, migration up/down within the new empty-database baseline, and root
  acceptance.
  Resolve rather than suppress all new type/RBI diagnostics.
- Record release-bound OpenCode/runtime evidence, tests, known live/operator gaps, and
  rollback/disable procedure in the handoff.

## Security and permission boundary

- Global OpenCode configuration is operator-managed; project configuration cannot
  override Commander or read its credential material.
- Bridge capabilities are user/conversation-scoped, short-lived, non-reusable, and
  checked before stream, steer, cancel, and result actions. Command proofs also bind
  the request id and canonical command body; the desktop main process obtains them
  from an operator-owned issuer and never returns them to the renderer.
- Runtime stream delivery is a distinct authenticated channel. It uses an
  operator-owned runtime identity over a private OS-owned socket or mutually
  authenticated service path; it never shares a panel proof or public user-action
  endpoint. Local tests use in-memory random one-use proofs only.
- Kirei authenticates the caller and derives actor/origin; tool-supplied actor IDs,
  project scope, due times, and outcomes are not trusted.
- Scheduling records contain references and task text only. Provider login state,
  server passwords, runtime credentials, and mobile pairing material never enter Git,
  images, logs, fixtures, or this plan.
- The scheduled worker has no authority to start project work, merge, deploy, or
  modify a repository solely because a task became due.

## Dependencies and blockers

1. **Blocking now:** the tested OpenCode `2.0.27` global plugin is server-only and
   cannot provide the required top-bar, transparent conversation, or trusted bridge
   capability without DOM injection. The maintained UI patch is selected and
   implemented as a source artifact; compile/live UI verification and a reviewed
   desktop capability exchange remain required before it can connect to the isolated
   bridge core or any runtime/Kirei boundary. The core's passing local tests do not
   clear this gate.
2. Obtain a release-bound OpenCode binary/CLI inspection in the target server
   environment; the local service is protected and its executable is not on PATH.
3. Select and prove the remote-web/pairing mobile access path and a disposable remote
   Git environment with operator access.
4. Record the selected future supported UI surface and rerun Gate 1 on that exact
   release before implementation. Do not substitute a different model or claim one.
5. Resolve the intentionally open first-release learning policy: automatic vs
   user-confirmed memory and staged vs automatic skill changes. The implementation
   must keep the setting explicit until the product owner selects it.

## Review checklist

- Does the OpenCode gate require a supported interface rather than a working DOM hack?
- Can any tool or scheduled retry duplicate a visible Commander result or due action?
- Does Kirei remain completely off the ordinary project-chat path?
- Are all future-task state transitions, cancellation races, and uncertain external
  results represented explicitly and testable?
- Is legacy removal delayed until a direct OpenCode alternative is proven, while still
  avoiding unnecessary compatibility migration afterward?

## Review record — 2026-10-12

- **Architecture review:** reviewed the specification, current Compose/bootstrap,
  routes, composition, job kinds, migrations, CI, and integration fixtures. It
  required a persistent bridge delivery contract, explicit state transitions,
  capability issuance, a greenfield schema decision, and a deletion inventory. All
  plan issues were resolved. The later release-bound probe failed Gate 1 because the
  active local plugin exposes only server capability; this is a product/platform
  blocker, not a plan defect.
- **Kirei backend review:** reviewed the current job lease semantics, worker,
  configuration, routes, migrations, and strict-type boundaries. It required
  task/execution/attempt separation, an idempotent post-delivery disposition,
  capability and mutation contracts, timezone/DST behavior, and worker/composition
  cutover coverage. All design-level P0 findings were resolved.
- **Claude Code review:** the installed direct CLI `2.1.267`, authenticated through
  the existing account, ran two read-only passes with `--model opus --effort medium`.
  Both responses report canonical model `claude-opus-5-5` (first-party). The Gate 1
  pass found no blocker but required reproducible desktop/remote-web probe evidence
  and a distinction between failed and unproven. The subsequent live plugin probe
  established the pinned release as server-only and Gate 1 as failed. The FutureTasks
  pass found no blocker and required an
  `awaiting_disposition` state, an `uncertain` exit, same-key reconciliation, and one
  coherent reschedule model; all are incorporated above. The final rereview required
  a versioned `resolve_uncertain` path, reschedule-time validation, final failed
  tasks, a CLI checksum, and the hard-stop capability criterion; all are incorporated
  above. It also noted the baseline migration wording, now clarified.
- **Claude Code patch review:** verified canonical `claude-opus-5-5` at medium
  effort. It required a default lazy-panel export, non-silent no-session behavior,
  closable panel tab, patch hashes, and wording that permits the selected maintained
  patch while preserving the no-DOM rule. Those issues are fixed. It explicitly
  agrees that Gate 1 must remain incomplete until the patch compiles/runs and the
  durable bridge/capability contract exists.
- **Claude Code patch rereview:** verified the implementation fixes at the same
  `claude-opus-5-5` medium setting. It found no code blocker; its final stale
  criterion wording was corrected after the rereview. It again confirms that the
  uncompiled UI shell cannot clear Gate 1.
- **Claude Code transport review attempt — 2026-10-13:** invoked the installed
  `claude` CLI `2.1.287` with `--model opus --effort medium` for a read-only review
  of the bridge transport. The sandboxed attempt reported `Not logged in`; the
  existing-session attempt produced no review text. No model response is recorded,
  so this is not represented as an Opus review or review approval. The local bridge
  changes instead have strict isolated TypeScript and deterministic loopback evidence
  recorded in the Gate contract.

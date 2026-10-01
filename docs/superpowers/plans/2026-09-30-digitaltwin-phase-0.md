# Digitaltwin Phase 0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A containerized, self-hosted agent fleet delivers code and research results through Campfire with approval bound to their exact revisions.

**Architecture:** Kirei forms a modular Ruby monolith with separate web and worker processes. The maintained Campfire Rails fork runs separately. Both use one PostgreSQL server with separate databases and roles. Herdr controls four CLIs in a shared non-root runtime container. Campfire and Git are the only interfaces to independent deployments.

**Tech Stack:** Ruby, Kirei, Sorbet, Rack/Puma, Sequel, PostgreSQL, Campfire Rails/Active Record, Campfire Redis/Resque, Docker Compose, Herdr, Wagglebot, Codex CLI, Claude Code, OpenCode, Gemini CLI.

**Spec:** [Phase 0 agent fleet specification](../../agent-fleet-architecture-and-review.md).

## Global Constraints

The following values and limits come from the spec; all tasks must comply with them.

- Host target: `Ubuntu 24.04 LTS on AMD64`; no required minimum memory or fleet concurrency limit.
- Prefer Alpine for Kirei. Initially retain the Campfire upstream base image; choose the Runtime base after Herdr/CLI validation.
- Three application images: Kirei, Runtime, and maintained Campfire. Production selects OCI digests; the repository provides development/integration Compose only.
- Exact tool/package versions in manifests; Kirei Ruby `4.0.7`; Campfire retains its independent upstream Ruby pin. Wagglebot requires Node.js ≥22.20, npm, and Git.
- Campfire uses a separate database and role on the same PostgreSQL server. Keep its Rails migrations separate from Kirei's Sequel migrations.
- Campfire retains Redis/Resque, Action Cable, cache, and Kredis through a Campfire-associated Redis sidecar container.
- Runtime: `No Docker socket`, `No privileged mode`, `No host root mount`, non-root, required volumes and networks.
- Default repository root: `/workspace/repos`; slug `owner/repository`; one workflow per verified Campfire thread. Multiple threads in a room can work at the same time.
- Each workflow uses a separate Git worktree under `/workspace/worktrees/<workflow-uuid>`. Its Writer and Reviewer share that worktree and branch.
- Bots: `@agent` and `@worker`, configurable. Writer and Reviewer share the Worker bot identity.
- Kirei posts Worker questions/progress through its durable outbox. Session-bound callbacks preserve verified thread routing and visible role identity.
- Writer/Reviewer require different underlying providers **and** base model families; default Codex/Claude Code.
- Every project workflow requires a spec, plan, reviews, and human approvals of the exact revisions.
- Three unsuccessful review rounds per gate block; Reviewer changes only the shared review Markdown file.
- One workflow branch, one final PR; no automatic merge and no automatic post-merge synchronization.
- All human room members are trusted collaborators with full capabilities, including approvals and destructive-operation confirmations. Configured local/peer bots cannot act as humans.
- Master: configurable `RoleConfig(cli, provider, model, family)` through Herdr and a local MCP bridge; Gemini CLI is the default. No direct provider API call or login through Campfire.
- Master chat handles operational conversation, status, coordination, and targeted emergency changes. It has no coding review/approval cycle; ordinary coding uses Writer/Reviewer workflows.
- Master context and operational access are shared across its fleet's rooms. Independent fleets retain separate Master sessions and private runtime/control data.
- Master-created workflow threads are optional in Phase 0. Keep existing-thread starts available; defer complex creation integration to Phase 1.
- Memory only manually through `@agent`/base instructions; no cron, no required maintenance after each session.
- GitHub remains the selected Git host. Headscale/Tailscale remain the selected private access base.
- One shared Runtime trust domain; do not claim process or project isolation against malicious agents.
- Infrastructure is responsible for the public route/TLS, production orchestration, daily encrypted S3 backups, and 30-day bucket lifecycle.
- Backup alarm after two consecutive failures; login state, repositories, and unpushed work are excluded.

## Review Focus

1. Duplicate or delayed deliveries must not cause a second start, second approval, or second response (Tasks 3, 4, 7).
2. Room rename, slug traversal, and symlink escape must not reach other workspaces (Task 5).
3. Revision changes, concurrent approvals, and bot senders must not reuse stale approval (Tasks 7, 8).
4. A worker crash between an external effect and DB completion, and Herdr `unknown`, must not pretend that work is complete (Tasks 3, 6, 11).
5. Dispatch exclusion and Git validation protect the review snapshot. Session credentials prevent accidental callback mix-ups, not deliberate forgery within the shared Runtime (Task 8).

## Implementation Decisions and Prerequisites

- Generate Kirei bootstrap files with its CLI in an empty staging directory, then copy them into this repository without replacing the existing docs. Add the Gemfile and test setup separately.
- One Kirei Ruby codebase provides web, worker, `bin/digitaltwin` callback, and stdio MCP bridge. The Runtime includes its two small clients.
- Keep Kirei paths at repository root and the Campfire fork under `apps/campfire/`. Each application has independent dependencies, tests, migrations, and image builds.
- Connect Campfire and Kirei through authenticated HTTP/events. Do not share application tables or move workflow state into Rails.
- PostgreSQL Sequel transactions coordinate gates, session generations, jobs, inbox, and outbox. Network calls run outside short DB locks.
- Reviews reside in `docs/superpowers/reviews/<workflow-uuid>.md`; the UUID stays internal, while ordinary chat messages use project/phase and links.
- New workflow branches are named `digitaltwin/<workflow-uuid>`.
- Approval binds the exact reported artifact commit and expected Markdown path in its Git tree. Review commits do not replace the target commit. Every new artifact-ready report requires renewed review/human approval.
- Messages during review are stored but not sent to the Writer. Immediately acknowledge the queue through the deduplicated outbox. After review, deliver them after revision/phase checks.
- Pause blocks new step dispatches while the current step finishes. Persist verified completion results; resume revalidates the saved phase, revision, and gates.
- Destructive or irreversible Master operations use one-time, time-limited confirmations bound to sender, room, action, and parameter hash.
- Job defaults: 30-second lease, heartbeat every 10 seconds, at most five attempts, backoff of 1/5/15/60 seconds. Task 3 checks the effects of slow calls.
- Stale status after 60 seconds without a successful Herdr check; uncertain states remain explicitly uncertain.
- External calls without proof of idempotency are not blindly retried after an unknown result. Reconciliation or human decision resolves the state.
- Select and record Kirei, Herdr, CLI, Campfire, and PostgreSQL versions in Task 1. Do not invent releases or unverified socket methods.

## File Map and Shared Contracts

All application paths below are **planned as new**, unless marked as existing.

| Path | Responsibility |
| --- | --- |
| Generated: `app.rb`, `config.ru`, `lib/tasks/db.rake`, `Rakefile`, `.irbrc`, `config/routes.rb`, `app/controllers/base.rb`, `sorbet/config`, and base directories | Kirei CLI bootstrap, copied from empty staging directory |
| Added: `Gemfile`, `Gemfile.lock`, `.ruby-version`, `.nvmrc`, test setup | Reproducible Ruby and Node dependencies; runtime and local pins agree |
| `config/runtime-tools.lock.yml`, `config/deployment.example.yml` | Exact pins, non-secret configuration, bot/model identities |
| `db/migrate/001_jobs.rb` through `006_confirmations.rb` | Incremental migrations: jobs/inbox/outbox/audit (3), projects (5), sessions (6), workflows/approvals (7), reviews (8), confirmations (9) |
| `app/domains/{jobs,campfire,projects,workflows,reviews,runtime,forge,controller}/` | Typed entities, services, thin controllers, and adapters per domain |
| `bin/{web,worker,digitaltwin,mcp}` | Process entry points and controlled operations |
| `docker/{app,runtime}.Dockerfile`, `apps/campfire/Dockerfile`, `compose.yml`, `.dockerignore`, `.env.example` | Three OCI images and local integration |
| `apps/campfire/` | Maintained upstream Rails app with independent license, Ruby/dependency pins, PostgreSQL migrations, thread UI/API, event delivery, and tests |
| `docs/interfaces/campfire-fork.md` | Upstream SHA, patch inventory, database port evidence, and reviewed update procedure |
| `spec/{domains,integration,contracts}/`, `spec/fixtures/` | Unit, PostgreSQL, adapter, and end-to-end evidence |
| `docs/{interfaces,operations,acceptance}/` | Contracts, operations, validation results, infrastructure handoff |
| `AGENTS.md`, `.agents/changelog.md`, `CHANGELOG.md` | Workflow rules and summaries, not a second task queue |
| `README.md` (existing) | Development commands and links |

Shared types in `app/domains/workflows/entities.rb`:

- `Actor(user_id: String, room_id: String, member: Boolean, bot: Boolean)`; from verified Campfire context, never set freely by the model.
- `RoleConfig(cli: String, provider: String, model: String, family: String)`; the Writer/Reviewer pair checks both differences.
- `ArtifactRef(kind: spec|plan|implementation|review, commit: String, path: String?)`; `path` is required for specification, plan, and review Markdown. Implementation uses `path: nil` with an exact target commit and frozen merge-base.
- `SessionRef(workflow_id: String?, generation: Integer, role: writer|reviewer|controller, pane_id: String, alias: String)`; writer/reviewer require a workflow ID, while controller has none.
- `Outcome(status: accepted|blocked|rejected|confirmation_required, reason: String, links: Array[String])`.
- Workflow states: `spec_writing → spec_review → spec_human_approval → plan_writing → plan_review → plan_human_approval → implementation → implementation_review → pr_ready → done → closed`; additionally `blocked`, `paused`, `cancelled` with the previous state stored.
- `done` means verified delivery of an open PR/research result, not a merge. `closed` follows only explicit thread-specific `@worker finish` and archives Herdr session metadata. Revisions and approvals remain traceable in the audit.

### Required State Transitions

Every transition checks workflow version, current phase, and verified event identity. This table defines gate progression; lifecycle commands apply separately.

| From | Event and guard | To |
| --- | --- | --- |
| `spec_writing`, `plan_writing`, `implementation` | Valid artifact-ready callback; clean worktree; Writer settled; review lock persisted | Corresponding `*_review` |
| `spec_review`, `plan_review`, `implementation_review` | Verified `changes_requested`; fewer than three unsuccessful rounds at this gate | Corresponding writing phase; implementation returns to `implementation` |
| Any review phase | Third verified unsuccessful round at this gate | `blocked`; request human direction |
| `spec_review`, `plan_review` | Verified approving review of current artifact revision | Corresponding `*_human_approval` |
| `spec_human_approval` | Authorized human approves the exact reviewer-approved specification commit | `plan_writing` |
| `plan_human_approval` | Authorized human approves the exact reviewer-approved plan commit | `implementation` |
| Any human approval phase | Artifact revision changes | Corresponding writing phase; previous approval cannot advance work |
| `implementation_review` | Verified approving review of the frozen implementation target | `pr_ready` |
| `pr_ready` | `Delivery.finalize` verifies push, final PR, and delivery evidence | `done` |
| `done` | Explicit thread-specific `finish`; Runtime reconciled and sessions stopped/archived | `closed` |
| Active workflow | Thread-specific `pause`; persist dispatch suppression and underlying phase | `paused`; current dispatched step may finish |
| `paused` | Verified current-step completion/callback | Remain paused; record result, revision, underlying phase, and blockers under normal transition rules |
| `paused` | Thread-specific `resume`; revalidate saved phase/revision and Runtime | Restore saved phase; dispatch only if its normal gates permit |

Research uses the same gates. Its `implementation` produces research Markdown, and its final delivery includes the workflow PR.
Pause suppresses dispatch, not verified result handling. Resume cannot clear a block or bypass a gate.
Cancellation retains its separate stop/reconciliation requirements.

### Schema and Uniqueness Sketch

Each task adds its own migration and database constraints before its services use those tables.

| Task / migration | Required records and constraints |
| --- | --- |
| 3 / `001_jobs.rb` | Jobs: unique dispatch key, lease token, lease expiry, attempts. Inbox: unique delivery ID and unique verified `(room_id, post_id)`. Outbox: unique response key. Audit records verified actor and event identity. |
| 5 / `002_projects.rb` | Projects: unique verified room ID, repository slug, and verified remote identity. Multiple workflows may reference the same project. |
| 6 / `003_sessions.rb` | Sessions: role, generation, pane, alias, configuration, and workflow identity. Unique `(workflow_id, role, generation)` for project sessions. |
| 7 / `004_workflows.rb` | Workflows: room/thread/project, branch, worktree path, phase, version, artifact revisions, archive time. Unique `(room_id, thread_id)` while unarchived; unique branch and worktree path. Approvals: unique `(workflow_id, kind, target_commit)`, verified human/message identity, timestamp. Add session-to-workflow foreign keys. |
| 8 / `005_reviews.rb` | Reviews: unique `(workflow_id, gate, round)`, frozen target/base commits, review commit, verdict, reviewer session/generation, review lock. |
| 9 / `006_confirmations.rb` | Confirmations: unique one-time token, sender/room/action/parameter hash, expiry, consumed time. Consume atomically when recording authorized dispatch; reconcile uncertain external results. |

Use workflow version checks and transactions with these constraints. Release thread reservations only after session reconciliation and archival.
These keys prevent duplicate application effects; they do not guarantee exactly-once external calls.

## Task 1: Interface Validation and Version Manifest

**Files:** Import `apps/campfire/` from a verified upstream commit during implementation. Modify its database/search, message/thread, webhook, UI, build, and test files. Create `config/runtime-tools.lock.yml`, `docs/interfaces/{herdr,campfire,campfire-fork,cli-startup}.md`, `spec/contracts/{herdr,campfire}_spec.rb`, `spec/fixtures/contracts/`.

**Interfaces:** Produces documented, release-bound Herdr operations for start, prompt, status, stop/archive, and Campfire authentication, membership, webhook ID, post ID, and thread or root post ID.

### Campfire Fork and PostgreSQL Preparation

Source baseline inspected: [`basecamp/once-campfire@90b3300`](https://github.com/basecamp/once-campfire/tree/90b330024dec3e757c79b6a7e6568f93da8e3148).
Its [search concern](https://github.com/basecamp/once-campfire/blob/90b330024dec3e757c79b6a7e6568f93da8e3148/app/models/message/searchable.rb) uses SQLite FTS5 `MATCH` and `rowid`.
Its initial migration creates an FTS5 virtual table; its [backup script](https://github.com/basecamp/once-campfire/blob/90b330024dec3e757c79b6a7e6568f93da8e3148/script/admin/prepare-backup) calls `SQLite3::Backup`.
This evidence defines port work, not a claim that changing the adapter is sufficient.

- [ ] Verify and pin the imported upstream commit. Preserve MIT notices, separate Ruby/Gemfile pins, and upstream history provenance.
- [ ] Record the local patch inventory and repeatable upstream update procedure. Review security fixes and rerun fork tests before publication.
- [ ] Add the PostgreSQL driver and connection configuration for development, test, performance, and production. Remove SQLite-specific timeout/transaction settings.
- [ ] Make schema creation and migration history PostgreSQL-compatible, including the initial FTS5 migration. Test fresh creation and incremental migration separately.
- [ ] Replace FTS5/index callbacks with PostgreSQL search. Test stemming, multiple terms, rich-text normalization, updates/deletes, message ordering, and room access filtering.
- [ ] Keep Active Storage attachment files in their persistent volume. Verify PostgreSQL blob/attachment records and file access after restart and restore.
- [ ] If existing SQLite data must migrate, plan offline export/import with preserved IDs, reset sequences, counts, foreign keys, and attachment integrity.
- [ ] Retain a verified source snapshot until import and restore checks pass. Fresh installations require no SQLite database.
- [ ] Replace or remove `script/admin/prepare-backup` and `hooks/{pre-backup,post-restore}` database-file behavior. Document infrastructure-owned PostgreSQL backup/restore instead.
- [ ] Update setup, Docker dependencies, CI services, and storage documentation for PostgreSQL. Preserve media-loader protections unrelated to the database adapter.
- [ ] Retain Redis/Resque, Action Cable, cache, and Kredis behavior. Move Redis hosting to its Campfire sidecar without replacing these backends.
- [ ] Remove the fork's embedded Redis process from `Procfile`. Configure Resque, Action Cable, caching, and Kredis for the sidecar address.
- [ ] Validate each Redis client configuration; upstream defaults include localhost. Test sidecar restart without reporting uncertain jobs as completed.
- [ ] Test PostgreSQL schema constraints, concurrent message writes, authentication, membership, attachments, and existing unit/system suites.
- [ ] Add root/reply relationships with same-room validation and foreign keys. Define migration behavior for existing unthreaded messages.
- [ ] Extend thread routes, bot posting/history, mobile views, pagination, and Turbo/Action Cable updates. Reject replies targeting another room.
- [ ] Assess optional Master thread creation. Record whether creation returns a verified root identity and supports retry reconciliation with a stable request key.
- [ ] If creation needs complex integration, defer it to `docs/phase-1-voice-controller.md`. Existing-thread starts remain the required Phase 0 path.
- [ ] Add authenticated events for subscribed rooms, including ordinary replies. Kirei routes active threads and ignores unactivated messages.
- [ ] Define signed event payloads with delivery identity, timestamp, verified sender/role, room, post, and root/thread identity.
- [ ] Keep webhook authentication secrets separate from bot reply credentials. Test invalid signatures, replay, revoked membership, and forged identities.
- [ ] Test simultaneous threads, correct bot reply placement, duplicate delivery, and local-bot suppression. Preserve existing mention and DM behavior.
- [ ] From `apps/campfire/`, run `bin/ci` with PostgreSQL and Redis. Adapt upstream CI paths; test migrations and image startup.
- [ ] Commit the reviewed fork baseline and PostgreSQL port separately from thread/event changes during implementation.

### Runtime and Chat Contract Evidence

- [ ] Check selected releases against official documentation and installed artifacts. Record exact versions, origin, and digests/checksums. Select an exact supported Node release ≥22.20.0 for `.nvmrc`.
- [ ] Write contract tests `starts_four_clis`, `writer_settles_after_ready`, `unknown_is_not_idle`, `selected_master_calls_local_mcp`, `campfire_verifies_delivery_and_sender`.
- [ ] Verify webhook delivery for ordinary human replies without repeated mentions. Record server-authenticated thread/root identity and bot reply placement.
- [ ] Prove an early disposable slice: Campfire mention → queued dispatch → one CLI through Herdr → bot reply in the source thread.
- [ ] Record slice commands and sanitized evidence before Tasks 3–5. Use temporary spike fixtures, not production workflow code or real project changes.
- [ ] Start all four CLIs with test credentials through Herdr. Record ready→idle/done, crash, timeout, and Gemini-specific screen state, without real project changes.
- [ ] Check the selected Master CLI's MCP round trip with `list_projects` and source room context. Check a fresh session with the same configuration.
- [ ] Save sanitized request/response fixtures and reproducible commands. Expect start, prompt, status, and stop evidence for each CLI.
- [ ] After Task 2, run `bundle exec rspec spec/contracts`; expect PASS against the validated fixtures. Task 1 provides recorded live checks before that.
- [ ] Block Tasks 6–10 if the API, idle handshake, webhook authentication, verified thread identity, or selected Master CLI's MCP is missing. Document a concrete alternative instead of inventing socket methods.
- [ ] After review, commit: `docs: validate pinned runtime and chat contracts`.

## Task 2: Kirei Foundation and Local Images

**Files:** Generate Kirei bootstrap files from the file map; create `Gemfile`, `Gemfile.lock`, `.ruby-version`, `.nvmrc`, test setup, `docker/app.Dockerfile`, `compose.yml`, `.env.example`, `.gitignore`, `spec/integration/boot_spec.rb`.

**Interfaces:** Reuses Kirei's generated `GET /livez` and `GET /readyz`, and produces `bin/web`, `bin/worker`, `bundle exec rake db:migrate`. `/readyz` checks database connectivity; pending migrations block process startup before serving.

- [ ] Create a temporary bootstrap bundle with the Task 1 Kirei pin. From an empty staging directory, run `BUNDLE_GEMFILE=<absolute-bootstrap-Gemfile> bundle exec kirei new "Digitaltwin"`. Copy generated files into this repository while preserving existing docs.
- [ ] Add the absent Gemfile, lockfile, and test setup. Write `4.0.7` in `.ruby-version` and the exact Task 1 Node release in `.nvmrc`; match both pins in manifests/images. [Ruby 4.0.7 release](https://www.ruby-lang.org/en/news/2026/09/15/ruby-4-0-7-released/).
- [ ] Write `boot_spec`: generated `/livez` returns 200; `/readyz` returns 503 on a Sequel connection error and 200 when `SELECT 1` succeeds. Assert pending migrations make `bin/web` and `bin/worker` exit before serving or dispatching jobs.
- [ ] Run `bundle exec rspec spec/integration/boot_spec.rb`; expect failure because `bin/web` and `bin/worker` startup integration is missing, not because health routes are missing.
- [ ] Add `bin/web` and `bin/worker` startup validation. Reject pending migrations before either process serves requests or dispatches jobs.
- [ ] Prefer an Alpine Kirei base image. If the pinned dependencies fail on Alpine, record the evidence before selecting Ubuntu. Pin Bundler and set up Sorbet.
- [ ] Define Compose services `web`, `worker`, `postgres`, `campfire`, `campfire-redis`, and later `runtime`. Use no real secrets or production routing.
- [ ] Keep Redis service connectivity private. Give `campfire-redis` a health check and persistent data volume; validate restart recovery.
- [ ] Provision separate Kirei/Campfire databases and roles locally. Test that each role cannot read or modify the other database.
- [ ] Check generated routes register `Router.add_health_routes!`. Run `docker compose config --quiet`, image builds, the boot test, and `bundle exec spoom srb tc`.
- [ ] After review, commit: `build: bootstrap Kirei control plane and local compose`.

## Task 3: Durable Jobs, Inbox, and Outbox

**Files:** Create `db/migrate/001_jobs.rb`, `app/domains/workflows/entities.rb`, `app/domains/jobs/{entities,worker,store}.rb`, `app/domains/campfire/outbox.rb`, `spec/domains/jobs_spec.rb`.

**Interfaces:** `Jobs.enqueue(kind: String, payload: Hash, key: String) -> String`; `Jobs.claim(worker_id: String, now: Time) -> Job?`; `complete(id:, lease_token:)`; `retry(id:, lease_token:, error:)`. `Outbox.enqueue(room_id:, thread_id: String?, bot:, role: String?, body:, key:) -> String`. PostgreSQL jobs dispatch Herdr work, reconciliation, and outbox delivery beyond the webhook request; Kirei needs no Sidekiq or Redis.

- [ ] Write PostgreSQL tests: two workers never claim the same job; a unique key returns one job; an expired lease is retryable; an old lease token cannot complete a job.
- [ ] Define and type-check all shared workflow contracts before Tasks 4–6 consume them. Add the Task 3 schema constraints above.
- [ ] Add `transaction_rollback_discards_state_and_outbox`, `fifth_failure_blocks`, `effect_succeeded_before_crash`, and `unknown_post_result`: rollback leaves neither state nor outbox row; five failed attempts block; unknown effects do not issue a duplicate network call before reconciliation.
- [ ] Run `bundle exec rspec spec/domains/jobs_spec.rb`; expect missing schema/store.
- [ ] Implement short `FOR UPDATE SKIP LOCKED` claims, lease/heartbeat, bounded retry values, and atomic state change plus outbox. Dispatch a long agent session, then release the job; reconcile completion separately.
- [ ] Check actual PostgreSQL concurrency, retry budget, and dead workers. Treat a crash after an unconfirmed network effect as blocked or uncertain; do not claim exactly-once external delivery.
- [ ] After review, commit: `feat: add durable leased jobs and delivery outbox`.

## Task 4: Campfire Routing and Verified Senders

**Files:** Create `app/domains/campfire/{controller,client,router,actor_resolver,worker_chat}.rb`, `spec/domains/campfire_spec.rb`; extend `bin/digitaltwin` and Task 3 outbox.

**Interfaces:** `Router.ingest(delivery: VerifiedDelivery) -> Outcome`; `ActorResolver.resolve(room_id:, user_id:) -> Actor`; `VerifiedDelivery` contains verified room, post, and thread or root post identity. Client methods follow Task 1 exactly.

`WorkerChat.post(session: SessionRef, body: String, key: String) -> Outcome` accepts session-bound questions and progress.
Runtime command: `digitaltwin say --text <text> --key <stable-message-key>` through the private Kirei endpoint.
Kirei derives room/thread, active role, and Worker bot identity from its session mapping. Callback parameters cannot supply another destination.
Deduplicate `(session, generation, key)` and reject a reused key with changed body. Audit the mapping and enqueue delivery transactionally.
Workflow notices require a verified thread; Master replies may use source-room context without a project thread.

- [ ] Write tests for invalid webhooks, own bots, peer bots, room membership, replay, and duplicate delivery.
- [ ] Write `worker_question_reaches_bound_thread`, `worker_role_visible`, `callback_retry_posts_once`, `callback_changed_body_rejected`, and `cross_workflow_destination_rejected`.
- [ ] Validate session credential/generation and active role before enqueueing Worker output. Keep Campfire credentials in Kirei, outside model output and Runtime callbacks.
- [ ] Reuse Task 8's callback authentication mechanism when integrated. Its credentials prevent accidental mix-ups within the shared Runtime, not malicious isolation.
- [ ] Check `agent_any_room_preserves_source`, `worker_unactivated_thread_does_not_start`, `worker_thread_routes_without_repeat_mention`, and `worker_thread_cannot_route_to_another_workflow`; ordinary messages expose no internal workflow IDs.
- [ ] Run `bundle exec rspec spec/domains/campfire_spec.rb`; expect missing router.
- [ ] Implement `@agent` to Master and thread-specific `@worker start`/`approve`/`pause`/`resume`/`finish`/`cancel`/ordinary message to the active project phase. Activate only the thread root with `@worker start`; route later human thread messages without a repeated mention. Store inbox before dispatch.
- [ ] Persist messages received while paused. On resume, dispatch them only after phase/revision checks and normal workflow gates.
- [ ] Check that sender/bot classification comes from Campfire; forged JSON/model fields cannot grant human authority.
- [ ] Validate the maintained fork's signed events against the Task 1 contract. Reject cross-room root identities before workflow dispatch.
- [ ] After review, commit: `feat: route authenticated Campfire mentions`.

## Task 5: Enrollment and Git Workspace

**Files:** Create `db/migrate/002_projects.rb`, `app/domains/projects/{enroll,repository_identity,workspace}.rb`, `app/domains/forge/client.rb`, `spec/domains/projects_spec.rb`, `bin/digitaltwin` enrollment.

**Interfaces:** `Projects.enroll(actor: Actor, room_id: String, slug: String, choice: clone|create_private|stop) -> Outcome`; `Workspace.resolve(slug: String) -> String`; `Forge.clone(slug:, destination:)`, `create_private(slug:)`, `read_revision(repo:, commit:)`.

`Workspace.resolve` returns the enrolled shared clone. `Workspace.for_workflow(slug:, workflow_id:, branch:) -> String` creates or verifies the workflow worktree.
Validate UUID, branch ownership, remote identity, and realpath containment under `/workspace/worktrees`. Never switch the shared clone for project work.

- [ ] Write `valid_slug_maps_path`, `rejects_traversal_and_symlink_escape`, `remote_mismatch_blocks`, `rename_keeps_room_mapping`.
- [ ] Add `two_threads_same_repo_isolated_worktrees`, `worktree_symlink_escape_rejected`, and `workflow_worktree_restart_verified` with local Git fixtures.
- [ ] Concurrent worktrees use separate branches. Writer edits in one cannot alter another workflow's HEAD, files, or review snapshot.
- [ ] For a missing repo, add exactly clone/create-private/stop; create privately only after the selected action, never implicitly.
- [ ] Run `bundle exec rspec spec/domains/projects_spec.rb`; expect missing enrollment services.
- [ ] Implement validated `owner/repository` segments, realpath-based containment checks, and remote identity for HTTPS/SSH. Use argv instead of composed shell strings.
- [ ] Connect chat, MCP, and shell to the same service. Initialize Wagglebot after Task 6 before a project workflow starts.
- [ ] Check with bare Git fixtures whose HEAD explicitly points to main; tests create no GitHub resources.
- [ ] After review, commit: `feat: enroll rooms into verified Git workspaces`.

## Task 6: Non-root Runtime, Herdr, and Wagglebot

**Files:** Create `db/migrate/003_sessions.rb`, `docker/runtime.Dockerfile`, `config/runtime-entrypoint.sh`, `app/domains/runtime/{herdr_client,sessions,reconcile}.rb`, `spec/{domains/runtime_spec.rb,integration/runtime_spec.rb}`.

**Interfaces:** `Sessions.start(workflow_id: String?, generation:, role:, config: RoleConfig, repo: String?) -> SessionRef`; `send_prompt(session:, text:, dispatch_key:)`; `state(session:) -> idle|done|working|unknown|missing`; `stop(session:)`. Writer/reviewer require non-null workflow ID and repo; controller requires both null and starts in the neutral Runtime home.

- [ ] Write runtime checks: UID ≠ 0, all four CLIs exist, no forbidden mounts/capabilities, socket only on the shared worker volume.
- [ ] Write `unknown_never_completes`, `old_generation_cannot_receive_prompt`, `restart_reconciles_panes` using Task 1 fixtures.
- [ ] Test `Sessions.start` rejects missing workflow ID or repo for writer/reviewer and rejects either value for controller. Check controller working directory is the neutral Runtime home.
- [ ] Pass the verified workflow worktree as `repo` for Writer/Reviewer. Persist it across session generations and revalidate it after restart.
- [ ] Install the `digitaltwin say` client with artifact-ready callbacks. Test a Writer question, human reply, and follow-up without direct Campfire credentials.
- [ ] Persist clone and worktree roots on the same workspace volume. Verify Git common-directory paths remain valid after container restart.
- [ ] Run `bundle exec rspec spec/domains/runtime_spec.rb`; expect missing session interface.
- [ ] Implement adapters only against the Task 1 contract. Persist Role→Pane/Alias, session generation, and separate credential areas in the shared Runtime home.
- [ ] Select the Runtime image base after testing pinned Herdr and all CLIs on Alpine. Record the dependency or runtime failure that requires Ubuntu, if any.
- [ ] Build the image with pinned tools, OpenSSH, and Wagglebot. Match `.ruby-version` and `.nvmrc` to image versions. Setup: `connect <company-git-url>`, `update --wagglebot`, per repo `init` and `update`.
- [ ] Provide upgrades only through an explicit operator command. Document interactive provider login; test persistence after container restart.
- [ ] Check `docker compose build runtime` and `docker compose run --rm runtime bin/runtime-smoke`; this new command checks versions/UID and Herdr CLI start. Authenticated provider checks remain separate operator checks.
- [ ] After review, commit: `feat: add persistent Herdr runtime and provisioning`.

## Task 7: Deterministic Workflows and Approvals

**Files:** Create `db/migrate/004_workflows.rb`, `app/domains/workflows/{machine,approvals,start}.rb`, `spec/domains/workflows_spec.rb`, `AGENTS.md`. Reuse Task 3 entities.

**Interfaces:** `Workflows.start(actor:, project_id:, thread_id:, writer: RoleConfig, reviewer: RoleConfig) -> Outcome`; `pause(actor:, workflow_id:, expected_version:)`; `resume(actor:, workflow_id:, expected_version:)`; `finish(actor:, workflow_id:, expected_version:)`; `transition(workflow_id:, event:, expected_version:)`; `Approvals.approve(actor:, workflow_id:, kind:, target_commit:) -> Outcome`.

- [ ] Write table-driven tests for all permitted/forbidden state transitions, spec/plan approval, and the reviewer prerequisite.
- [ ] Add `same_family_across_cli_rejected`, `same_provider_rejected`, `bot_approval_rejected`, `artifact_change_invalidates`, `concurrent_approval_advances_once`, `active_thread_second_start_rejected_without_sessions`, `new_thread_starts_fresh_sessions`, `finish_only_delivered`, `unknown_blocks_finish`, and `cancel_reconciles_before_archive`.
- [ ] Add `pause_allows_current_step_completion`, `pause_blocks_next_dispatch`, `paused_callback_preserves_result`, `resume_revalidates_revision`, and `resume_cannot_clear_block_or_skip_gate`.
- [ ] Run `bundle exec rspec spec/domains/workflows_spec.rb`; expect missing state machine.
- [ ] Implement state changes with workflow lock/version and audit. Contextual approval binds the presented revision on receipt, not a later moved HEAD.
- [ ] Check approval rejects a missing specification/plan path in the reported commit tree, a changed target commit, and a dirty worktree. Do not add file upload or blob storage.
- [ ] A thread-specific start creates fresh Writer/Reviewer sessions on one branch in its workflow worktree. Another thread uses its own worktree.
- [ ] Reserve the active thread transactionally before creating sessions. Reject duplicate starts; uncertain creation remains reserved until reconciled.
- [ ] Keep pause/resume/cancel/finish orthogonal to approvals. `finish` closes only a delivered workflow after an explicit command and stops/archives its sessions. Resume must not skip gates; idle chat does not end or start anything automatically.
- [ ] Persist pause under the workflow lock before further dispatch. Let current work settle; record verified results and phase progress while paused.
- [ ] Apply the same pause guard to chat, MCP, review-start, and subsequent workflow jobs. Continue reconciliation and required result notifications.
- [ ] Resume the saved phase/revision only after normal checks. Keep uncertain Runtime states blocked and approvals bound to current artifacts.
- [ ] Anchor required spec/plan rules in AGENTS.md; technical enforcement stays in Kirei.
- [ ] After review, commit: `feat: enforce revision-bound workflow gates`.

## Task 8: Artifact-ready and Mutually Exclusive Reviews

**Files:** Create `db/migrate/005_reviews.rb`, `app/domains/reviews/{coordinator,callback,verdict}.rb`, `bin/digitaltwin` callback, `spec/domains/reviews_spec.rb`.

**Interfaces:** `Reviews.ready(session: SessionRef, artifact: ArtifactRef) -> Outcome`; `begin(workflow_id:, target:)`; `finish(session:, review_commit:, verdict: approve|changes_requested) -> Outcome`. CLI: `digitaltwin artifact-ready --kind <kind> --commit <sha>` and `review-ready --commit <sha> --verdict <verdict>`.

- [ ] Write `callback_wrong_session_rejected`, `dirty_writer_blocks`, `writer_working_or_unknown_blocks`, `queued_writer_prompt_not_dispatched`.
- [ ] Add `queued_message_acknowledged_once` and `implementation_review_uses_frozen_base`. A queued-message reply states that delivery waits for review completion.
- [ ] Add `missing_artifact_path_rejected` and `review_diff_other_file_rejected`. Check the exact target commit tree, Reviewer diff of review file only, append-only sections, real review identities, and block on the third failure.
- [ ] Run `bundle exec rspec spec/domains/reviews_spec.rb`; expect missing coordinator.
- [ ] Stop new Writer dispatches, send transition prompt, verify callback/artifact/commit/cleanliness and settled Herdr state. Persist review lock before Reviewer start.
- [ ] Bind the callback to a short-lived session credential and generation; do not trust model text or Herdr lifecycle events alone.
- [ ] Document that all agents share one UID. Credentials prevent accidental crossed callbacks; Git checks detect target changes and unauthorized review diffs.
- [ ] Freeze `merge-base(default_branch, target_commit)` when implementation review begins. Review that base→target diff; record both commits in the review section.
- [ ] Compare the Reviewer commit with the frozen HEAD; diffs in other files block the round. A section contains provider/model/family, target, findings, verdict, and timestamp.
- [ ] Pass verified review path/commit to Writer; unlock only for the correction phase. Revalidate pending messages and gate revision.
- [ ] Check that all three gates use the same rules and bot/prompt instructions cannot bypass the lock.
- [ ] After review, commit: `feat: coordinate immutable artifact review rounds`.

## Task 9: Master and Local MCP Bridge

**Files:** Create `db/migrate/006_confirmations.rb`, `app/domains/controller/{tools,confirmations,master}.rb`, `bin/mcp`, `spec/domains/controller_spec.rb`; update `docs/phase-1-voice-controller.md` if thread creation is deferred.

**Interfaces:** Master `RoleConfig(cli: String, provider: String, model: String, family: String)` reaches `Sessions.start(workflow_id: nil, generation:, role: controller, config:, repo: nil)` unchanged. MCP tools `list_projects`, `list_workflows`, `get_workflow`, `enroll_project`, `start_workflow`, `send_prompt`, `pause_workflow`, `resume_workflow`, `finish_workflow`, `cancel_workflow`, `git_action`, `deployment_action`, `delete_resource`, `change_credentials` receive server-side Actor/Room/Thread context.

Master conversation and targeted emergency operations do not enter the project specification, plan, review, or approval cycle.
Starting or prompting a coding workflow is coordination; the target workflow retains its own gates.
Emergency operations use available typed tools. Keep existing destructive/irreversible confirmations; add no emergency-specific approval gate.
`start_workflow` requires a verified thread in the selected project room.
If optional creation is enabled, Kirei first creates/reconciles the thread and records its association before calling the same workflow-start service.
Keep source actor/context verified; preserve normal coding gates. The Master does not infer a target from unrelated room messages.

- [ ] Write `selected_master_config_reaches_sessions_start`: assert controller role, `workflow_id: nil`, `repo: nil`, and unchanged CLI/provider/model/family. Assert another Task 1-validated CLI/provider reaches the same interface unchanged.
- [ ] Write `room_context_survives_tool_call`, `restart_creates_fresh_session_with_same_config`, `secret_values_never_returned`. Assert restart uses the same config in neutral Runtime home, reconstructs PostgreSQL status, and preserves sender/context checks.
- [ ] Add `rooms_share_master_context` and `peer_private_context_unavailable`. Preserve source/sender checks while allowing fleet-wide context and operations.
- [ ] Add `bot_cannot_confirm`, `confirmation_replay_rejected`, `changed_parameters_require_confirmation`, `unconfigured_deployment_tool_rejected`.
- [ ] Test `master_status_needs_no_workflow` and `master_emergency_operation_needs_no_coding_cycle`. Ordinary coding still requires approved workflow revisions.
- [ ] Test `master_starts_in_verified_existing_thread` independently of optional thread creation.
- [ ] If Task 1 confirms straightforward creation, test verified association, duplicate requests, and uncertain-result reconciliation before enabling it.
- [ ] Otherwise record deferral and keep existing-thread starts. Do not block Phase 0 acceptance on automatic thread creation.
- [ ] Run `bundle exec rspec spec/domains/controller_spec.rb`; expect missing Master/MCP server.
- [ ] Implement the stdio MCP bridge against the same application services, with no raw shell or credential-read tools.
- [ ] Route MCP `send_prompt` through the same review lock and queue as chat. Test that a Master request cannot bypass Writer exclusion.
- [ ] Serialize requests to one logical Master session with shared fleet context and access. Pass verified source context through a request-bound capability.
- [ ] Keep independent fleets' Master sessions and private control/runtime data separate. Peer collaboration uses only shared Campfire and Git interfaces.
- [ ] Require a second human confirmation before destructive/irreversible operations. The confirmation window is ten minutes; audit includes the parameter hash, never secret values.
- [ ] Accept confirmation from any verified human room member. Add `collaborator_can_confirm`; do not introduce an owner-only ID or human allowlist.
- [ ] Check the selected Master CLI's real MCP round trip from Task 1. After restart, PostgreSQL/tool status is authoritative, not the old conversation.
- [ ] After review, commit: `feat: add authorized master operations`.

## Task 10: Verified Delivery, Research, Memory, and Peer Handoffs

**Files:** Create `app/domains/forge/{delivery,memory}.rb`, `app/domains/campfire/peer_handoff.rb`, `docs/operations/project-runbook.md`, `spec/domains/delivery_spec.rb`.

**Interfaces:** `Delivery.finalize(workflow_id:, commit:, evidence:) -> Outcome`; `Memory.change(actor:, slug:, path:, mode: additive|reorganization) -> Outcome`; `PeerHandoff.receive(actor:, recipient:, slug:, revision:, action:) -> Outcome`.

- [ ] Write `one_branch_one_pr`, `research_requires_sources_and_uncertainty`, `no_automatic_merge_or_pull`, `failed_push_not_delivered`.
- [ ] Add configurable memory slug, additive default-branch change, and reorganization only by branch/PR; a workflow may finish without memory needs.
- [ ] Check peer with its own Git identity: verified remote/revision, no access to private paths/API, and no self-bot loop.
- [ ] Run `bundle exec rspec spec/domains/delivery_spec.rb`; expect missing delivery logic.
- [ ] Implement the final PR only after implementation review. Deliver commit, check evidence, blockers, and links; an open PR counts as a delivery result.
- [ ] Document research paths `docs/research/<topic>.md` and sources, access date, and uncertainty; spec/plan gates also apply to research.
- [ ] Define `CHANGELOG.md` as the human result summary and `.agents/changelog.md` as the agent change log. Neither contains scheduler state.
- [ ] Check with a simulated Campfire peer and local Git remotes; no second server fleet is required. Real push/PR/memory checks require separate authorization.
- [ ] After review, commit: `feat: deliver reviewed artifacts and scoped peer handoffs`.

## Task 11: Recovery and Operational Status

**Files:** Create `app/domains/runtime/recovery.rb`, `app/domains/controller/status.rb`, `spec/integration/recovery_spec.rb`.

**Interfaces:** `Recovery.run(now: Time) -> RecoveryReport`; `Status.snapshot(project_id:, now:) -> StatusSnapshot` with phase, revision, session state, activity, PR, blocker, evidence, and staleness.

- [ ] Write crash matrix: before/after session start, callback, review lock, approval, Git push, and Campfire post. Uncertain external effects block for reconciliation without an unverified retry.
- [ ] Add missing pane, unknown provider state, old alias, and DB recovery with missing workspace; never mark automatically as done.
- [ ] Run `bundle exec rspec spec/integration/recovery_spec.rb`; expect missing reconciliation.
- [ ] Implement startup reconciliation from DB, Git, and Herdr; create a fresh Master. Reconstruct work from committed artifacts and reviews.
- [ ] Restore paused dispatch suppression after restart. Reconcile the current step and preserve its result without starting the next step.
- [ ] Test recovery with the ignored Superpowers ledger absent. When any project role needs a fresh session, restore phase, approved revisions, and review context.
- [ ] Mark status stale after 60 seconds without a verified Runtime check. Surface blocked jobs and phases through a deduplicated outbox.
- [ ] Check container restart with named volumes; two threads in one room and two independent rooms work at the same time. Finish only one delivered thread with explicit `finish` and check that its Herdr sessions are archived.
- [ ] After review, commit: `feat: reconcile runtime state after interruption`.

## Task 12: Portable Operations Contracts and Infrastructure Handoff

**Files:** Create `docs/operations/{containers,private-access,backup-restore,secrets}.md`, `spec/integration/image_contract_spec.rb`; Modify `README.md`, `compose.yml`.

**Interfaces:** Contract documents list ENV, secret file, UID/GID, volumes, ports, healthcheck, and start command per image. Worker/Runtime require the same host/task socket volume.

- [ ] Write `image_contract_spec`: non-root, healthcheck, persistent paths, no Docker/root mounts, no publicly exposed Runtime SSH ports, and version pins matching `.ruby-version`/`.nvmrc`. Assert Alpine Kirei or recorded dependency evidence for Ubuntu; assert the Runtime base follows Task 6 validation.
- [ ] Check Campfire's image against `apps/campfire/.ruby-version` and its lockfile. Keep image build and test contexts independent from Kirei.
- [ ] Run `bundle exec rspec spec/integration/image_contract_spec.rb`; expect missing complete image contracts.
- [ ] Document one PostgreSQL server with separate Kirei/Campfire databases, roles, migrations, and secrets. Campfire is a separate maintained application service.
- [ ] Document Campfire Redis/Resque, Action Cable, cache, and Kredis through a Redis sidecar. Scope Kirei's no-Redis requirement to Kirei.
- [ ] Define Redis service address, health check, persistent volume, restart, and backup/restore contracts. Keep its port on private service connectivity.
- [ ] Enable and validate Redis persistence for queued jobs; upstream disables AOF and snapshots. Reconcile uncertain effects after restart or restore.
- [ ] Document three independently built images and Campfire's upstream base/pins. Infrastructure owns production orchestration; local Compose supplies integration services.
- [ ] Describe private Tailscale/OpenSSH access, Headscale DNS-only through Traefik with trusted TLS; neither Cloudflare Proxy nor Tunnel for Headscale.
- [ ] Document intentional raw terminal access: the human controls agents directly. No owner-side status/approval CLI or Master session is required for attachment.
- [ ] State that terminal input is unsupervised. Kirei's dispatch lock cannot prevent direct input; conflicting changes require review reconciliation.
- [ ] Document ignored `.env`, optional `op://` references, and root/0600 production files in the infrastructure repo. No secret values or login states in images/Git.
- [ ] Create backup/restore matrix: include both PostgreSQL databases/roles, Campfire attachments/Redis data, Herdr, configuration/audit, and Headscale; exclude clones/worktrees/unpushed work/CLI logins.
- [ ] Replace SQLite file-copy procedures with consistent PostgreSQL database backups and coordinated attachment restore. Verify relationships and application startup after restore.
- [ ] Hand off daily S3 client-side encryption, external key, 30-day lifecycle, and second-failure alarm to Infra. Explicitly document re-login after restore.
- [ ] Document an image-by-digest example for Production Compose and Hosted Task, including shared socket. Do not present portability as a tested ECS deployment.
- [ ] After review, commit: `docs: define production image and recovery contracts`.

## Task 13: End-to-end Acceptance and Release Evidence

**Files:** Create `spec/integration/phase0_spec.rb`, `bin/acceptance`, `docs/acceptance/phase0.md`; Modify `README.md`, `CHANGELOG.md`, `.agents/changelog.md`.

**Interfaces:** `bin/acceptance local` checks local flows with simulated providers/peer; `bin/acceptance operator` creates a live checklist to complete manually and starts no deployment.

- [ ] Write local full flow: two rooms, mobile interview response, spec review/approval, plan review/approval, implementation review, and one PR delivery.
- [ ] Add research flow, optional pushed memory change, peer handoff, and restart between gates. Forbidden approvals/transitions must fail.
- [ ] Run `docker compose run --rm web bundle exec rspec spec/integration/phase0_spec.rb`; expect missing full integration before implementation.
- [ ] Complete full integration and run `bundle exec rspec`, `bundle exec spoom srb tc`, `bundle exec rubocop`, `docker compose config --quiet`, and image builds.
- [ ] From `apps/campfire/`, run `bin/ci` and PostgreSQL migration/restore checks. Complete two mobile interviews without crossed replies or repeated mentions.
- [ ] Record output, commit, image digests, and test environment. Report live checks and simulated checks separately.
- [ ] After separate deployment approval, the operator checks real CLIs, Campfire mobile access, Tailnet attachment, externally closed SSH port, all service health checks, and encrypted restore.
- [ ] Check every acceptance row below; missing live evidence remains open and must not imply Phase 0 acceptance.
- [ ] After review, commit: `test: document Phase 0 acceptance evidence`.

## Acceptance Matrix for Spec §25

| No. | Responsibility | Required evidence |
| --- | --- | --- |
| 1 | 12/13 + Infra | published OCI digests start in existing infrastructure; separate approval |
| 2 | 1/2/13 | local Compose integration with fork, separate PostgreSQL databases, and Campfire Redis sidecar; exit 0 |
| 3 | 12 | same ENV/volume/health contracts, Compose and Hosted Task definition |
| 4 | 6/12/13 + Infra | health of Campfire, DB, Web, Worker, Runtime, Headscale, Tailscale |
| 5–6 | 6/12 | contract test and inspected container UID/mount/capability state |
| 7 | 6/11 | host restart, persistent clones/worktrees/Herdr/Wagglebot/login states |
| 8 | 1/6 | four real CLI starts through pinned Herdr |
| 9–10 | 12/13 + Infra | Tailnet attachment succeeds; external SSH connection test is rejected |
| 11 | 4/9 | Master request from two rooms carries the correct source room |
| 12–13 | 5/6/7 | fresh role sessions; duplicate active-thread start rejected; concurrent same-repo threads use separate worktrees |
| 14–16 | 5 | path/remote checks, three setup actions, one shared service |
| 17–19 | 7 | revision/bot/race negative tests |
| 20–24 | 8 | immutable target/base commits, handshake, Writer lock, queued-message acknowledgement, review handoff, third failure |
| 25–26 | 10 | one branch/PR, no automatic merge |
| 27 | 9/11 | fresh selected-controller session with same configuration and durably reconstructed status |
| 28 | 10/13 | simulated peer and separate Git identity, chat/Git only |
| 29 | 1/12/13 + Infra | encrypted restore of both databases/roles and attachments; logins not restored |
| 30 | 1/4/6/13 + Operator | mobile thread interviews through session-bound Kirei outbox, visible Worker role, authenticated ordinary replies |
| 31 | 10/13 | committed research Markdown with sources and uncertainty |
| 32 | 10/13 + Operator | memory commit and push verified for configured repo identity |

## Open Decisions

1. **Herdr capability:** Task 1 determines whether four CLIs and the idle handshake are reliable enough. Without proof, do not implement Runtime/review based on assumptions.
2. **Pins and credentials:** Operator provides company config, memory slug, model configuration, and test credentials. Secrets stay outside the plan. Select release pins after checking them.
3. **Campfire contract:** Implement and validate the approved Rails fork, PostgreSQL port, Redis sidecar, thread UI/API, and authenticated events. Validate Worker callbacks through Kirei's outbox. Missing secure sender/thread checks block human approval.
4. **Infrastructure:** Production, image publication, Headscale, backup bucket, and restore test are separately authorized work in the infrastructure context. This plan provides contracts only.
5. **Review exclusion:** Kirei prevents prompt dispatch, checks Git, and monitors Herdr. The accepted shared Runtime domain does not protect against intentional direct terminal/filesystem access. Such access blocks/invalidates review and does not count as approved work.

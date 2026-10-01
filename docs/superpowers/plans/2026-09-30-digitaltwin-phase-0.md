# Digitaltwin Phase 0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A containerized, self-hosted agent fleet delivers code and research results through Mattermost with approval bound to their exact revisions.

**Architecture:** Kirei forms a modular Ruby monolith with separate web, worker, and event-listener processes. The official, unmodified Mattermost Team Edition server runs separately; Kirei uses external bots and authenticated APIs. Both use one PostgreSQL server with separate databases and roles. Herdr controls four CLIs in a shared non-root runtime container. Mattermost and Git are the only interfaces to independent deployments.

**Tech Stack:** Ruby, Kirei, Sorbet, Rack/Puma, Sequel, PostgreSQL, Mattermost Team Edition, Mattermost push proxy, custom mobile builds, Docker Compose, Herdr, Wagglebot, Codex CLI, Claude Code, OpenCode, Gemini CLI.

**Spec:** [Phase 0 agent fleet specification](../../agent-fleet-architecture-and-review.md).

## Global Constraints

The following values and limits come from the spec; all tasks must comply with them.

- Host target: `Ubuntu 24.04 LTS on AMD64`; no required minimum memory or fleet concurrency limit.
- Prefer Alpine for Kirei. Use the official Team Edition artifact; choose the Runtime base after Herdr/CLI validation.
- Build two application images: Kirei and Runtime. Integrate upstream Team Edition and push-proxy artifacts separately. Production selects OCI digests; the repository provides development/integration Compose only.
- Exact tool/package versions in manifests; Kirei Ruby `4.0.7`; chat and mobile releases have independent upstream pins. Wagglebot requires Node.js ≥22.20, npm, and Git.
- Mattermost uses a separate database and role on the same PostgreSQL server. Keep upstream server migrations separate from Kirei's Sequel migrations.
- Use our own signed mobile builds and the existing self-hosted Mattermost push proxy/APNs/FCM path. No Kirei push service.
- Exclude commercially licensed components and Calls/rtcd. Phase 1 independently integrates LiveKit; Agents plugin MCP is not a dependency.
- Runtime: `No Docker socket`, `No privileged mode`, `No host root mount`, non-root, required volumes and networks.
- Default repository root: `/workspace/repos`; slug `owner/repository`; one workflow per verified Mattermost thread. Multiple threads in a channel can work at the same time.
- Each workflow uses a separate Git worktree under `/workspace/worktrees/<workflow-uuid>`. Its Writer and Reviewer share that worktree and branch.
- Bots: `@agent` and `@worker`, configurable. Writer and Reviewer share the Worker bot identity.
- Kirei posts Worker questions/progress through its durable outbox. Session-bound callbacks preserve verified thread routing and visible role identity.
- Detailed updates stay in project threads. Important summaries/blockers also reach the configured Master chat with source/workflow links; do not mirror full streams.
- Writer/Reviewer require different underlying providers **and** base model families; default Codex/Claude Code.
- A worker session is an LLM conversation/context. Reuse only within the same workflow topic, role, and configuration; unrelated work starts fresh.
- Every project workflow requires a spec, plan, reviews, and human approvals of the exact revisions.
- Three unsuccessful review rounds per gate block; Reviewer changes only the shared review Markdown file.
- One workflow branch, one final PR; no automatic merge and no automatic post-merge synchronization.
- All human channel members are trusted collaborators with full capabilities, including approvals and destructive-operation confirmations. Configured local/peer bots cannot act as humans.
- Master: configurable `RoleConfig(cli, provider, model, family)` through Herdr and a local MCP bridge; Gemini CLI is the default. No direct provider API call or login through Mattermost.
- Master chat handles operational conversation, status, coordination, and targeted emergency changes. It has no coding review/approval cycle; ordinary coding uses Writer/Reviewer workflows.
- Master context and operational access are shared across its fleet's channels. Independent fleets retain separate Master sessions and private runtime/control data.
- Only Master initiates separately managed agent sessions. Workers/peers request human approval for another session; no autonomous peer chains. Harness-native subagents are allowed where supported.
- Master-created workflow threads are optional in Phase 0. Keep existing-thread starts available; defer complex creation integration to Phase 1.
- Memory only manually through `@agent`/base instructions; no cron, no required maintenance after each session.
- GitHub remains the selected Git host. Headscale/Tailscale remain the selected private access base.
- One shared Runtime trust domain; do not claim process or project isolation against malicious agents.
- Infrastructure is responsible for the public route/TLS, production orchestration, daily encrypted S3 backups, and 30-day bucket lifecycle.
- Backup alarm after two consecutive failures; login state, repositories, and unpushed work are excluded.

## Review Focus

1. Duplicate or delayed deliveries must not cause a second start, second approval, or second response (Tasks 3, 4, 7).
2. Channel rename, slug traversal, and symlink escape must not reach other workspaces (Task 5).
3. Revision changes, concurrent approvals, and bot senders must not reuse stale approval (Tasks 7, 8).
4. A worker crash between an external effect and DB completion, and Herdr `unknown`, must not pretend that work is complete (Tasks 3, 6, 11).
5. Dispatch exclusion and Git validation protect the review snapshot. Session credentials prevent accidental callback mix-ups, not deliberate forgery within the shared Runtime (Task 8).

## Implementation Decisions and Prerequisites

- Generate Kirei bootstrap files with its CLI in an empty staging directory, then copy them into this repository without replacing the existing docs. Add the Gemfile and test setup separately.
- One Kirei Ruby codebase provides web, worker, event listener, `bin/digitaltwin` callback, and stdio MCP bridge. The Runtime includes its two small clients; mobile build toolchains use their own build runners.
- Keep Kirei at repository root and planned custom mobile sources under `apps/mobile/`. Consume the official server artifact without a source fork.
- Connect Mattermost and Kirei through authenticated HTTP/events. Do not share application tables or move workflow state into the chat server.
- PostgreSQL Sequel transactions coordinate gates, session generations, jobs, inbox, and outbox. Network calls run outside short DB locks.
- Reviews reside in `docs/superpowers/reviews/<workflow-uuid>.md`; the UUID stays internal, while ordinary chat messages use project/phase and links.
- New workflow branches are named `digitaltwin/<workflow-uuid>`.
- Approval binds the exact reported artifact commit and expected Markdown path in its Git tree. Review commits do not replace the target commit. Every new artifact-ready report requires renewed review/human approval.
- Messages during review are stored but not sent to the Writer. Immediately acknowledge the queue through the deduplicated outbox. After review, deliver them after revision/phase checks.
- Pause blocks new step dispatches while the current step finishes. Persist verified completion results; resume revalidates the saved phase, revision, and gates.
- Destructive or irreversible Master operations use one-time, time-limited confirmations bound to sender, channel, action, and parameter hash.
- Job defaults: 30-second lease, heartbeat every 10 seconds, at most five attempts, backoff of 1/5/15/60 seconds. Task 3 checks the effects of slow calls.
- Stale status after 60 seconds without a successful Herdr check; uncertain states remain explicitly uncertain.
- External calls without proof of idempotency are not blindly retried after an unknown result. Reconciliation or human decision resolves the state.
- Select and record Kirei, Herdr, CLI, Mattermost, and PostgreSQL versions in Task 1. Do not invent releases or unverified socket methods.

## File Map and Shared Contracts

All application paths below are **planned as new**, unless marked as existing.

| Path | Responsibility |
| --- | --- |
| Generated: `app.rb`, `config.ru`, `lib/tasks/db.rake`, `Rakefile`, `.irbrc`, `config/routes.rb`, `app/controllers/base.rb`, `sorbet/config`, and base directories | Kirei CLI bootstrap, copied from empty staging directory |
| Added: `Gemfile`, `Gemfile.lock`, `.ruby-version`, `.nvmrc`, test setup | Reproducible Ruby and Node dependencies; runtime and local pins agree |
| `config/runtime-tools.lock.yml`, `config/deployment.example.yml` | Exact pins, non-secret configuration, bot/model identities |
| `db/migrate/001_jobs.rb` through `006_confirmations.rb` | Incremental migrations: jobs/inbox/outbox/audit (3), projects (5), sessions (6), workflows/approvals (7), reviews (8), confirmations (9) |
| `app/domains/{jobs,mattermost,projects,workflows,reviews,runtime,forge,controller}/` | Typed entities, services, thin controllers, and adapters per domain |
| `bin/{web,worker,chat-listener,digitaltwin,mcp}` | Process entry points and controlled operations |
| `docker/{app,runtime}.Dockerfile`, `compose.yml`, `.dockerignore`, `.env.example` | Kirei/Runtime builds and pinned upstream chat/push services for local integration |
| `apps/mobile/` | Planned custom Mattermost mobile builds, upstream pin/patch inventory, signing/distribution configuration, tests |
| `docs/interfaces/{mattermost,mobile-push,licenses}.md` | API/event recovery contract, custom mobile/push maintenance, artifact/dependency licenses and notices |
| `spec/{domains,integration,contracts}/`, `spec/fixtures/` | Unit, PostgreSQL, adapter, and end-to-end evidence |
| `docs/{interfaces,operations,acceptance}/` | Contracts, operations, validation results, infrastructure handoff |
| `AGENTS.md`, `.agents/changelog.md`, `CHANGELOG.md` | Workflow rules and summaries, not a second task queue |
| `README.md` (existing) | Development commands and links |

Shared types in `app/domains/workflows/entities.rb`:

- `Actor(user_id: String, channel_id: String, member: Boolean, bot: Boolean)`; from verified Mattermost context, never set freely by the model.
- `RoleConfig(cli: String, provider: String, model: String, family: String)`; the Writer/Reviewer pair checks both differences.
- `ArtifactRef(kind: spec|plan|implementation|review, commit: String, path: String?)`; `path` is required for specification, plan, and review Markdown. Implementation uses `path: nil` with an exact target commit and frozen merge-base.
- `SessionRef(workflow_id: String?, generation: Integer, role: writer|reviewer|controller, pane_id: String, alias: String)`; writer/reviewer require a workflow ID, while controller has none. Pane/alias identify Runtime execution; they do not prove LLM conversation identity or safe reuse.
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
| 3 / `001_jobs.rb` | Jobs: unique dispatch key, lease token, lease expiry, attempts. Inbox: unique verified `(channel_id, post_id, event_kind, post_revision)`; persist reconciliation checkpoints and source identity. Outbox: unique response key. Audit records verified actor and event identity. |
| 5 / `002_projects.rb` | Projects: unique verified channel ID, repository slug, and verified remote identity. Multiple workflows may reference the same project. |
| 6 / `003_sessions.rb` | Sessions: role, generation, pane, alias, configuration, and workflow identity. Unique `(workflow_id, role, generation)` for project sessions. |
| 7 / `004_workflows.rb` | Workflows: channel/thread/project, branch, worktree path, phase, version, artifact revisions, archive time. Unique `(channel_id, thread_id)` while unarchived; unique branch and worktree path. Approvals: unique `(workflow_id, kind, target_commit)`, verified human/message identity, timestamp. Add session-to-workflow foreign keys. |
| 8 / `005_reviews.rb` | Reviews: unique `(workflow_id, gate, round)`, frozen target/base commits, review commit, verdict, reviewer session/generation, review lock. |
| 9 / `006_confirmations.rb` | Confirmations: unique one-time token, sender/channel/action/parameter hash, expiry, consumed time. Consume atomically when recording authorized dispatch; reconcile uncertain external results. |

Use workflow version checks and transactions with these constraints. Release thread reservations only after session reconciliation and archival.
These keys prevent duplicate application effects; they do not guarantee exactly-once external calls.

## Task 1: Interface Validation and Version Manifest

**Files:** Create `config/runtime-tools.lock.yml`, `docs/interfaces/{herdr,mattermost,mobile-push,licenses,cli-startup}.md`, `spec/contracts/{herdr,mattermost}_spec.rb`, `spec/fixtures/contracts/`. Plan `apps/mobile/` from a verified upstream mobile revision; do not import or rebuild the server.

**Interfaces:** Document release-bound Herdr operations and Mattermost bot REST/WebSocket authentication, post/root/channel/user identity, membership, and history reconciliation.

### Team Edition, Mobile Push, and License Validation

- [ ] Pin the official Team Edition artifact and push proxy by release/digest. Verify the actual artifact's compiled license and notices.
- [ ] Audit bundled plugins, transitive dependencies, source headers, and build outputs. Exclude commercially licensed components entirely.
- [ ] Keep the official server unmodified. Any proposed source build requires separate AGPL/commercial dependency review and approval.
- [ ] Omit Calls/rtcd and the Agents plugin from required services. Never remove license checks or copy paid modules into replacements.
- [ ] Record a repeatable server/mobile/push security-update procedure, upstream provenance, compatibility matrix, and patch inventory.
- [ ] Verify bot API permissions and authenticated WebSocket visibility on Team Edition; test ordinary thread replies without repeated mentions.
- [ ] Validate post `id`, `root_id`, `channel_id`, sender identity, membership, and thread retrieval against REST responses.
- [ ] Persist durable inbox identities/checkpoints; test REST backfill after disconnect, overlap deduplication, edits/deletions, and revoked membership.
- [ ] Test two simultaneous threads, correct bot replies, uncertain post reconciliation, and local-bot suppression.
- [ ] Assess optional Master root-post creation with verified association and stable-request reconciliation. Defer complex integration to Phase 1.
- [ ] Pin the Apache 2.0 mobile source. Define application IDs, branding, signing, distribution, update pipeline, and license/NOTICE retention.
- [ ] Use Mattermost's existing push proxy with matching APNs/FCM configuration; do not implement a push gateway inside Kirei.
- [ ] Document future human Apple/Google enrollment, signing/push credentials, distribution choice, rotation, and recovery; store no secrets in Git.
- [ ] Validate our iOS/Android builds, foreground/background push, reconnect, thread deep links, and notification payload/privacy settings.
- [ ] Define a reproducible mobile build/CI pipeline from the pinned upstream source; include iOS and Android build runners.
- [ ] Separate offline CI checks from device/network/credential-dependent operator checks. Missing evidence remains open.

### Runtime and Chat Contract Evidence

- [ ] Check selected releases against official documentation and installed artifacts. Record exact versions, origin, and digests/checksums. Select an exact supported Node release ≥22.20.0 for `.nvmrc`.
- [ ] Write contract tests `starts_four_clis`, `writer_settles_after_ready`, `unknown_is_not_idle`, `selected_master_calls_local_mcp`, `mattermost_verifies_event_and_sender`.
- [ ] Verify authenticated event delivery for ordinary human replies without repeated mentions. Record server-authenticated thread/root identity and bot reply placement.
- [ ] Prove an early disposable slice: Mattermost mention → queued dispatch → one CLI through Herdr → bot reply in the source thread.
- [ ] Record slice commands and sanitized evidence before Tasks 3–5. Use temporary spike fixtures, not production workflow code or real project changes.
- [ ] Start all four CLIs with test credentials through Herdr. Record ready→idle/done, crash, timeout, and Gemini-specific screen state, without real project changes.
- [ ] Check the selected Master CLI's MCP round trip with `list_projects` and source channel context. Check a fresh session with the same configuration.
- [ ] Save sanitized request/response fixtures and reproducible commands. Expect start, prompt, status, and stop evidence for each CLI.
- [ ] After Task 2, run `bundle exec rspec spec/contracts`; expect PASS against the validated fixtures. Task 1 provides recorded live checks before that.
- [ ] Block Tasks 6–10 if the API, idle handshake, event authentication, verified thread identity, or selected Master CLI's MCP is missing. Document a concrete alternative instead of inventing socket methods.
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
- [ ] Define Compose services `web`, `worker`, `chat-listener`, `postgres`, `mattermost`, `push-proxy`, and later `runtime`. Pin upstream chat/push images. Use no real secrets or production routing.
- [ ] Give chat/push services explicit health/configuration contracts; keep credentials and internal API connectivity private.
- [ ] Provision separate Kirei/Mattermost databases and roles locally. Test that each role cannot read or modify the other database.
- [ ] Check generated routes register `Router.add_health_routes!`. Run `docker compose config --quiet`, image builds, the boot test, and `bundle exec spoom srb tc`.
- [ ] After review, commit: `build: bootstrap Kirei control plane and local compose`.

## Task 3: Durable Jobs, Inbox, and Outbox

**Files:** Create `db/migrate/001_jobs.rb`, `app/domains/workflows/entities.rb`, `app/domains/jobs/{entities,worker,store}.rb`, `app/domains/mattermost/outbox.rb`, `spec/domains/jobs_spec.rb`.

**Interfaces:** `Jobs.enqueue(kind: String, payload: Hash, key: String) -> String`; `Jobs.claim(worker_id: String, now: Time) -> Job?`; `complete(id:, lease_token:)`; `retry(id:, lease_token:, error:)`. `Outbox.enqueue(channel_id:, thread_id: String?, bot:, role: String?, body:, key:) -> String`. PostgreSQL jobs dispatch Herdr work, reconciliation, and outbox delivery beyond event ingestion; Kirei needs no Sidekiq or Redis.

- [ ] Write PostgreSQL tests: two workers never claim the same job; a unique key returns one job; an expired lease is retryable; an old lease token cannot complete a job.
- [ ] Define and type-check all shared workflow contracts before Tasks 4–6 consume them. Add the Task 3 schema constraints above.
- [ ] Add `transaction_rollback_discards_state_and_outbox`, `fifth_failure_blocks`, `effect_succeeded_before_crash`, and `unknown_post_result`: rollback leaves neither state nor outbox row; five failed attempts block; unknown effects do not issue a duplicate network call before reconciliation.
- [ ] Run `bundle exec rspec spec/domains/jobs_spec.rb`; expect missing schema/store.
- [ ] Implement short `FOR UPDATE SKIP LOCKED` claims, lease/heartbeat, bounded retry values, and atomic state change plus outbox. Dispatch a long agent session, then release the job; reconcile completion separately.
- [ ] Check actual PostgreSQL concurrency, retry budget, and dead workers. Treat a crash after an unconfirmed network effect as blocked or uncertain; do not claim exactly-once external delivery.
- [ ] After review, commit: `feat: add durable leased jobs and delivery outbox`.

## Task 4: Mattermost Routing and Verified Senders

**Files:** Create `app/domains/mattermost/{client,listener,reconcile,router,actor_resolver,worker_chat}.rb`, `spec/domains/mattermost_spec.rb`; create `bin/chat-listener`; extend `bin/digitaltwin` and Task 3 outbox.

**Interfaces:** `Router.ingest(delivery: VerifiedDelivery) -> Outcome`; `ActorResolver.resolve(channel_id:, user_id:) -> Actor`; `VerifiedDelivery` contains server-verified channel, post, root, sender, event kind, and post revision. Client methods follow Task 1 exactly.
`thread_id` is the verified root post ID. Event identities support REST backfill; they are not invented webhook delivery IDs.

`WorkerChat.post(session: SessionRef, body: String, key: String) -> Outcome` accepts session-bound questions and progress.
Runtime command: `digitaltwin say --text <text> --key <stable-message-key>` through the private Kirei endpoint.
Kirei derives channel/thread, active role, and Worker bot identity from its session mapping. Callback parameters cannot supply another destination.
Deduplicate `(session, generation, key)` and reject a reused key with changed body. Audit the mapping and enqueue delivery transactionally.
Workflow notices require a verified thread; Master replies may use source-channel context without a project thread.

- [ ] Write tests for invalid events, own bots, peer bots, channel membership, replay, duplicate delivery, disconnect/backfill, and edits/deletions.
- [ ] Write `worker_question_reaches_bound_thread`, `worker_role_visible`, `callback_retry_posts_once`, `callback_changed_body_rejected`, and `cross_workflow_destination_rejected`.
- [ ] Keep detailed Worker updates in their bound thread. Master summaries use the configured verified destination and Agent bot identity.
- [ ] Validate session credential/generation and active role before enqueueing Worker output. Keep Mattermost credentials in Kirei, outside model output and Runtime callbacks.
- [ ] Reuse Task 8's callback authentication mechanism when integrated. Its credentials prevent accidental mix-ups within the shared Runtime, not malicious isolation.
- [ ] Check `agent_any_channel_preserves_source`, `worker_unactivated_thread_does_not_start`, `worker_thread_routes_without_repeat_mention`, and `worker_thread_cannot_route_to_another_workflow`; ordinary messages expose no internal workflow IDs.
- [ ] Run `bundle exec rspec spec/domains/mattermost_spec.rb`; expect missing router.
- [ ] Implement `@agent` to Master and thread-specific `@worker start`/`approve`/`pause`/`resume`/`finish`/`cancel`/ordinary message to the active project phase. Activate only the thread root with `@worker start`; route later human thread messages without a repeated mention. Store inbox before dispatch.
- [ ] Persist messages received while paused. On resume, dispatch them only after phase/revision checks and normal workflow gates.
- [ ] Resolve server `is_bot` and configured bot identities through Mattermost. Neither unconfigured bots nor forged fields can grant human authority.
- [ ] Require migrated database state before `bin/chat-listener` ingests events. Keep its connection lifecycle separate from bounded job execution.
- [ ] Authenticate the WebSocket/REST source against Task 1. Reconcile disconnects with persisted checkpoints; reject cross-channel roots and revoked membership.
- [ ] After review, commit: `feat: route authenticated Mattermost mentions`.

## Task 5: Enrollment and Git Workspace

**Files:** Create `db/migrate/002_projects.rb`, `app/domains/projects/{enroll,repository_identity,workspace}.rb`, `app/domains/forge/client.rb`, `spec/domains/projects_spec.rb`, `bin/digitaltwin` enrollment.

**Interfaces:** `Projects.enroll(actor: Actor, channel_id: String, slug: String, choice: clone|create_private|stop) -> Outcome`; `Workspace.resolve(slug: String) -> String`; `Forge.clone(slug:, destination:)`, `create_private(slug:)`, `read_revision(repo:, commit:)`.

`Workspace.resolve` returns the enrolled shared clone. `Workspace.for_workflow(slug:, workflow_id:, branch:) -> String` creates or verifies the workflow worktree.
Validate UUID, branch ownership, remote identity, and realpath containment under `/workspace/worktrees`. Never switch the shared clone for project work.

- [ ] Store an explicit `channel_id` to repository slug mapping. Test valid Mattermost channel names without inferring slugs from names/display text.
- [ ] Write `valid_slug_maps_path`, `rejects_traversal_and_symlink_escape`, `remote_mismatch_blocks`, `rename_keeps_channel_mapping`.
- [ ] Add `two_threads_same_repo_isolated_worktrees`, `worktree_symlink_escape_rejected`, and `workflow_worktree_restart_verified` with local Git fixtures.
- [ ] Concurrent worktrees use separate branches. Writer edits in one cannot alter another workflow's HEAD, files, or review snapshot.
- [ ] For a missing repo, add exactly clone/create-private/stop; create privately only after the selected action, never implicitly.
- [ ] Run `bundle exec rspec spec/domains/projects_spec.rb`; expect missing enrollment services.
- [ ] Implement validated `owner/repository` segments, realpath-based containment checks, and remote identity for HTTPS/SSH. Use argv instead of composed shell strings.
- [ ] Connect chat, MCP, and shell to the same service. Initialize Wagglebot after Task 6 before a project workflow starts.
- [ ] Check with bare Git fixtures whose HEAD explicitly points to main; tests create no GitHub resources.
- [ ] After review, commit: `feat: enroll channels into verified Git workspaces`.

## Task 6: Non-root Runtime, Herdr, and Wagglebot

**Files:** Create `db/migrate/003_sessions.rb`, `docker/runtime.Dockerfile`, `config/runtime-entrypoint.sh`, `app/domains/runtime/{herdr_client,sessions,reconcile}.rb`, `bin/runtime-smoke`, `spec/{domains/runtime_spec.rb,integration/runtime_spec.rb}`.

**Interfaces:** `Sessions.start(workflow_id: String?, generation:, role:, config: RoleConfig, repo: String?) -> SessionRef`; `send_prompt(session:, text:, dispatch_key:)`; `state(session:) -> idle|done|working|unknown|missing`; `stop(session:)`. Writer/reviewer require non-null workflow ID and repo; controller requires both null and starts in the neutral Runtime home.

- [ ] Write runtime checks: UID ≠ 0, all four CLIs exist, no forbidden mounts/capabilities, socket only on the shared worker volume.
- [ ] Write `unknown_never_completes`, `old_generation_cannot_receive_prompt`, `restart_reconciles_panes` using Task 1 fixtures.
- [ ] Guard session creation through Master-authorized dispatch. Kirei bootstraps/restores the configured Master; authorized workflow role/recovery dispatches cannot create unrelated work. Workers and peer bots cannot invoke independent starts.
- [ ] Test `worker_cannot_start_independent_session`, `peer_start_requires_human_then_master`, `authorized_review_recovery_keeps_workflow_scope`, and `harness_subagent_is_not_fleet_session`.
- [ ] Test `Sessions.start` rejects missing workflow ID or repo for writer/reviewer and rejects either value for controller. Check controller working directory is the neutral Runtime home.
- [ ] Verify each CLI's conversation identity and resume behavior against Task 1. Reuse requires matching workflow topic, role/configuration, and current generation.
- [ ] Test `same_workflow_role_reuses_healthy_context`, `unrelated_topic_starts_fresh_context`, `writer_reviewer_contexts_separate`, and `new_workflow_never_reuses_old_context`.
- [ ] Pass the verified workflow worktree as `repo` for Writer/Reviewer. Persist it across session generations and revalidate it after restart.
- [ ] Install the `digitaltwin say` client with artifact-ready callbacks. Test a Writer question, human reply, and follow-up without direct Mattermost credentials.
- [ ] Persist clone and worktree roots on the same workspace volume. Verify Git common-directory paths remain valid after container restart.
- [ ] Run `bundle exec rspec spec/domains/runtime_spec.rb`; expect missing session interface.
- [ ] Implement adapters only against the Task 1 contract. Persist Role→Pane/Alias, session generation, and separate credential areas in the shared Runtime home.
- [ ] Select the Runtime image base after testing pinned Herdr and all CLIs on Alpine. Record the dependency or runtime failure that requires Ubuntu, if any.
- [ ] Install the worker tool baseline below in the Runtime image. Check Writer and Reviewer shell environments, not only Kirei or entrypoint PATH.
- [ ] Build the image with pinned tools, OpenSSH, and Wagglebot. Match `.ruby-version` and `.nvmrc` to image versions. Setup: `connect <company-git-url>`, `update --wagglebot`, per repo `init` and `update`.
- [ ] Provide upgrades only through an explicit operator command. Document interactive provider login; test persistence after container restart.
- [ ] Check `docker compose build runtime` and `docker compose run --rm runtime bin/runtime-smoke`; this planned executable checks versions/UID, Herdr CLI start, and the functional tool cases below. Authenticated provider checks remain separate operator checks.
- [ ] After review, commit: `feat: add persistent Herdr runtime and provisioning`.

### Runtime Base and Lean Tool Baseline

The host remains Ubuntu 24.04; this choice concerns only the worker container.
Keep Task 6's conditional Alpine preference until pinned Herdr and all four CLIs pass startup and shell execution checks.
Do not infer container contents from an Ubuntu host or a full desktop installation.

| Candidate | Relevant tradeoff |
| --- | --- |
| Alpine | Small base, musl, BusyBox defaults. Install GNU tools explicitly; verify native CLI and project dependencies on musl. |
| Debian slim / Ubuntu minimal | glibc and familiar GNU packages reduce compatibility work for glibc-only tools. Install missing tools explicitly; omit recommended packages. |
| Omarchy | Arch/Hyprland desktop distribution with graphical applications. It provides no necessary benefit for this headless Runtime. |

Recommend testing Alpine first under the existing policy. If compatibility fails, compare Debian slim with Ubuntu minimal using the same smoke cases.
Record measured image size and the concrete dependency failure before selecting a fallback.
Using Debian instead of the existing Ubuntu fallback requires an explicit base-choice decision; this tool change does not make that decision.
For Alpine Claude Code, validate `libgcc`, `libstdc++`, and system ripgrep with `USE_BUILTIN_RIPGREP=0` against the pinned release.

Required command groups and Alpine package names:

| Tools | Package/source | Purpose |
| --- | --- | --- |
| `sh`, portable `awk`, `ps`, `kill`, `gzip` | Alpine base/BusyBox; verify installed applets | Small shell pipelines, process inspection, compression |
| `bash` | `bash` | Harness shell commands and scripts that require Bash |
| `cat`, `head`, `tail`, `wc`, `sort`, `uniq`, `cut`, `tr`, `cp`, `mv`, `rm`, `mkdir`, `mktemp`, `realpath`, `stat`, `sha256sum`, `timeout` | `coreutils` | Predictable GNU file, text, checksum, and bounded-command operations |
| `find`, `xargs`; `grep`; `sed`; `diff`, `cmp`; `patch` | `findutils`, `grep`, `sed`, `diffutils`, `patch` | Null-delimited file handling, text edits, and patch inspection |
| `rg`, `fd` | `ripgrep`, `fd` in community | Fast content and filename search |
| `jq`, `python3` | `jq`, `python3` | JSON queries and standard-library temporary scripts |
| `git`, `ssh` | Existing Git/OpenSSH provisioning | Worktrees, revisions, and existing Git transport |
| `curl`, trusted HTTPS | `curl`, `ca-certificates` | HTTP diagnostics and downloads |
| `file`; GNU `tar`; `zip`, `unzip` | `file`, `tar`, `zip`, `unzip` | File identification and common archive inspection/creation |

Alpine build additions: `bash coreutils findutils grep sed diffutils patch ripgrep fd jq python3 curl ca-certificates file tar zip unzip`.
Use `apk add --no-cache` with exact package versions recorded for the selected stable release and architecture.
Enable main/community from the same release; do not mix edge packages into the pinned stable image.
Already planned Git, OpenSSH, Ruby, Node/npm, Herdr, CLI, and Wagglebot packages remain in their existing provisioning steps.
Audit base-provided applets rather than assuming every image includes them; do not add duplicate download/search tools without a need.

Debian/Ubuntu use the same named packages except `fd-find` provides `fdfind`.
If that fallback is selected, expose `fd` with one image-build symlink and verify both names.
Use `apt-get install --no-install-recommends`; verify base-provided `awk`, gzip, and GNU utilities before omitting package additions.
Pin and record the selected release's package versions; clean package lists after the build.

Keep build toolchains, database clients, browser automation, `xz`, and third-party Python modules project-specific.
Add dependencies through reviewed image/project manifests; use a disposable project virtual environment when Python packages are required.
Do not run hidden global pip/npm installs during ordinary agent work.
The Python baseline requires neither pip nor a new harness, review service, or evaluation stack.

Extend the existing planned `bin/runtime-smoke` with these functional fixtures and failure assertions:

- [ ] Check the non-root user and Writer/Reviewer PATH; run offline commands using each role's shell configuration.
- [ ] Verify actual Writer/Reviewer CLI shell execution in the existing live operator checklist; offline shell checks alone do not prove integration.
- [ ] Verify GNU command implementations and versions. Test Bash pipelines and portable `sh`/`awk` separately.
- [ ] Search fixtures with `rg`, `fd`, and `grep`; include spaces, hidden files, and explicit ignore-policy choices.
- [ ] Round-trip filenames through `find -print0` and `xargs -0`. Check `sed` replacement and `sort`/`uniq` output.
- [ ] Check GNU `stat`, `realpath`, `sha256sum`, and a bounded `timeout` command against fixture expectations.
- [ ] Create a local Git repository and worktree, inspect a diff, and apply a patch only inside disposable fixtures.
- [ ] Parse and assert JSON with `jq`; run Python standard-library JSON/CSV/path/hash/subprocess operations.
- [ ] Serve a local fixture with Python, fetch it using `curl --fail`, and check failure for an error response.
- [ ] Verify the CA bundle exists and curl supports HTTPS. Keep external TLS checks in the explicit network-enabled integration suite.
- [ ] Inspect `file` output and round-trip tar/gzip and zip archives; compare extracted fixture contents.
- [ ] Use unique temporary directories and cleanup traps/finally blocks; verify cleanup after both success and failure.
- [ ] Set `PYTHONDONTWRITEBYTECODE=1` for temporary analysis. Check scratch operations leave the reviewed worktree unchanged.
- [ ] Retain Herdr startup checks; run credential-dependent live provider checks only through the existing operator checklist.

Package evidence checked on 2026-10-01: [Alpine package index](https://pkgs.alpinelinux.org/packages?branch=v3.23&arch=x86_64),
[Alpine ripgrep](https://pkgs.alpinelinux.org/package/v3.23/community/x86_64/ripgrep),
[Alpine fd](https://pkgs.alpinelinux.org/package/v3.23/community/x86_64/fd),
[Debian fd-find command naming](https://packages.debian.org/trixie/fd-find),
[Ubuntu fd-find](https://packages.ubuntu.com/noble/fd-find),
[Debian slim image scope](https://hub.docker.com/_/debian),
[Claude Code musl requirements](https://code.claude.com/docs/en/setup#alpine-linux-and-musl-based-distributions), and
[Omarchy's desktop scope](https://github.com/omacom/omarchy/blob/master/manual/01-welcome-to-omarchy.md).
These sources validate names and compatibility considerations; Task 1 still selects exact versions.

## Task 7: Deterministic Workflows and Approvals

**Files:** Create `db/migrate/004_workflows.rb`, `app/domains/workflows/{machine,approvals,start}.rb`, `spec/domains/workflows_spec.rb`, `AGENTS.md`. Reuse Task 3 entities.

**Interfaces:** `Workflows.start(actor:, project_id:, thread_id:, writer: RoleConfig, reviewer: RoleConfig) -> Outcome`; `pause(actor:, workflow_id:, expected_version:)`; `resume(actor:, workflow_id:, expected_version:)`; `finish(actor:, workflow_id:, expected_version:)`; `transition(workflow_id:, event:, expected_version:)`; `Approvals.approve(actor:, workflow_id:, kind:, target_commit:) -> Outcome`.

- [ ] Write table-driven tests for all permitted/forbidden state transitions, spec/plan approval, and the reviewer prerequisite.
- [ ] Add `same_family_across_cli_rejected`, `same_provider_rejected`, `bot_approval_rejected`, `artifact_change_invalidates`, `concurrent_approval_advances_once`, `active_thread_second_start_rejected_without_sessions`, `new_thread_starts_fresh_sessions`, `finish_only_delivered`, `unknown_blocks_finish`, and `cancel_reconciles_before_archive`.
- [ ] Add `pause_allows_current_step_completion`, `pause_blocks_next_dispatch`, `paused_callback_preserves_result`, `resume_revalidates_revision`, and `resume_cannot_clear_block_or_skip_gate`.
- [ ] Run `bundle exec rspec spec/domains/workflows_spec.rb`; expect missing state machine.
- [ ] Implement state changes with workflow lock/version and audit. Contextual approval binds the presented revision on receipt, not a later moved HEAD.
- [ ] Check approval rejects a missing specification/plan path in the reported commit tree, a changed target commit, and a dirty worktree. Do not add file upload or blob storage.
- [ ] Route verified human `@worker start` through Master-authorized creation without a second approval or separate Master-chat interaction. Bot starts are rejected; the authorized workflow includes its gated Writer/Reviewer lifecycle.
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

**Interfaces:** Master `RoleConfig(cli: String, provider: String, model: String, family: String)` reaches `Sessions.start(workflow_id: nil, generation:, role: controller, config:, repo: nil)` unchanged. MCP tools `list_projects`, `list_workflows`, `get_workflow`, `enroll_project`, `start_workflow`, `send_prompt`, `pause_workflow`, `resume_workflow`, `finish_workflow`, `cancel_workflow`, `git_action`, `deployment_action`, `delete_resource`, `change_credentials` receive server-side Actor/Channel/Thread context.

Master conversation and targeted emergency operations do not enter the project specification, plan, review, or approval cycle.
Starting or prompting a coding workflow is coordination; the target workflow retains its own gates.
Master owns creation of separately managed sessions. Workers/peers request human approval and Master executes the authorized creation; they cannot start sessions or peer chains autonomously.
Harness-native subagents are allowed where supported and stay subordinate to the invoking session.
Emergency operations use available typed tools. Keep existing destructive/irreversible confirmations; add no emergency-specific approval gate.
`start_workflow` requires a verified thread in the selected project channel.
If optional creation is enabled, Kirei first creates/reconciles the thread and records its association before calling the same workflow-start service.
Keep source actor/context verified; preserve normal coding gates. The Master does not infer a target from unrelated channel messages.

- [ ] Write `selected_master_config_reaches_sessions_start`: assert controller role, `workflow_id: nil`, `repo: nil`, and unchanged CLI/provider/model/family. Assert another Task 1-validated CLI/provider reaches the same interface unchanged.
- [ ] Write `channel_context_survives_tool_call`, `restart_creates_fresh_session_with_same_config`, `secret_values_never_returned`. Assert restart uses the same config in neutral Runtime home, reconstructs PostgreSQL status, and preserves sender/context checks.
- [ ] Add `channels_share_master_context` and `peer_private_context_unavailable`. Preserve source/sender checks while allowing fleet-wide context and operations.
- [ ] Add `bot_cannot_confirm`, `confirmation_replay_rejected`, `changed_parameters_require_confirmation`, `unconfigured_deployment_tool_rejected`.
- [ ] Test `master_status_needs_no_workflow` and `master_emergency_operation_needs_no_coding_cycle`. Ordinary coding still requires approved workflow revisions.
- [ ] Test `master_starts_in_verified_existing_thread` independently of optional thread creation.
- [ ] If Task 1 confirms straightforward creation, test verified association, duplicate requests, and uncertain-result reconciliation before enabling it.
- [ ] Otherwise record deferral and keep existing-thread starts. Do not block Phase 0 acceptance on automatic thread creation.
- [ ] Run `bundle exec rspec spec/domains/controller_spec.rb`; expect missing Master/MCP server.
- [ ] Implement the stdio MCP bridge against the same application services, with no raw shell or credential-read tools.
- [ ] Route MCP `send_prompt` through the same review lock and queue as chat. Test that a Master request cannot bypass Writer exclusion.
- [ ] Serialize requests to one logical Master session with shared fleet context and access. Pass verified source context through a request-bound capability.
- [ ] Keep independent fleets' Master sessions and private control/runtime data separate. Peer collaboration uses only shared Mattermost and Git interfaces.
- [ ] Require a second human confirmation before destructive/irreversible operations. The confirmation window is ten minutes; audit includes the parameter hash, never secret values.
- [ ] Accept confirmation from any verified human channel member. Add `collaborator_can_confirm`; do not introduce an owner-only ID or human allowlist.
- [ ] Check the selected Master CLI's real MCP round trip from Task 1. After restart, PostgreSQL/tool status is authoritative, not the old conversation.
- [ ] Configure and verify the Master chat destination. Summaries link to source project threads and artifacts without exposing internal workflow IDs.
- [ ] After review, commit: `feat: add authorized master operations`.

## Task 10: Verified Delivery, Research, Memory, and Peer Handoffs

**Files:** Create `app/domains/forge/{delivery,memory}.rb`, `app/domains/mattermost/peer_handoff.rb`, `docs/interfaces/peer-handoff.md`, `docs/operations/project-runbook.md`, `spec/domains/delivery_spec.rb`.

**Interfaces:** `Delivery.finalize(workflow_id:, commit:, evidence:) -> Outcome`; `Memory.change(actor:, slug:, path:, mode: additive|reorganization) -> Outcome`; `PeerHandoff.receive(actor:, version:, request_key:, recipient:, thread_id:, slug:, revision:, action:) -> Outcome`. Sender/source identity comes from verified Mattermost context, not untrusted envelope claims.

- [ ] Write `one_branch_one_pr`, `research_requires_sources_and_uncertainty`, `no_automatic_merge_or_pull`, `failed_push_not_delivered`.
- [ ] Add configurable memory slug, additive default-branch change, and reorganization only by branch/PR; a workflow may finish without memory needs.
- [ ] Document the initial versioned peer envelope: protocol version, stable request key, recipient, source message identity, requested action, existing workflow thread, repository slug, and branch/commit/PR reference. Verify sender, membership, target, and artifact with the receiving fleet's own credentials.
- [ ] Test unsupported versions, wrong recipients, duplicate requests, unverified revisions, bot `@worker start`, autonomous onward chains, and requests requiring human approval followed by Master creation.
- [ ] Permit handoffs only to existing workflows; never treat a peer message as human authorization. Do not add automatic hop/rate limits as an approval substitute.
- [ ] Check peer with its own Git identity: verified remote/revision, no access to private paths/API, and no self-bot loop.
- [ ] Run `bundle exec rspec spec/domains/delivery_spec.rb`; expect missing delivery logic.
- [ ] Implement the final PR only after implementation review. Deliver commit, check evidence, blockers, and links; an open PR counts as a delivery result.
- [ ] Document research paths `docs/research/<topic>.md` and sources, access date, and uncertainty; spec/plan gates also apply to research.
- [ ] Define `CHANGELOG.md` as the human result summary and `.agents/changelog.md` as the agent change log. Neither contains scheduler state.
- [ ] Check with a simulated Mattermost peer and local Git remotes; no second server fleet is required. Real push/PR/memory checks require separate authorization.
- [ ] After review, commit: `feat: deliver reviewed artifacts and scoped peer handoffs`.

## Task 11: Recovery and Operational Status

**Files:** Create `app/domains/runtime/recovery.rb`, `app/domains/controller/status.rb`, `spec/integration/recovery_spec.rb`.

**Interfaces:** `Recovery.run(now: Time) -> RecoveryReport`; `Status.snapshot(project_id:, now:) -> StatusSnapshot` with phase, revision, session state, activity, PR, blocker, evidence, and staleness.

- [ ] Write crash matrix: before/after session start, callback, review lock, approval, Git push, and Mattermost post. Uncertain external effects block for reconciliation without an unverified retry.
- [ ] Add missing pane, unknown provider state, old alias, and DB recovery with missing workspace; never mark automatically as done.
- [ ] Run `bundle exec rspec spec/integration/recovery_spec.rb`; expect missing reconciliation.
- [ ] Implement startup reconciliation from DB, Git, and Herdr; create a fresh Master. Reconstruct work from committed artifacts and reviews.
- [ ] Restore paused dispatch suppression after restart. Reconcile the current step and preserve its result without starting the next step.
- [ ] Test recovery with the ignored Superpowers ledger absent. When any project role needs a fresh session, restore phase, approved revisions, and review context.
- [ ] Reuse a verified healthy conversation after a wait only for the same workflow topic and role/configuration. Otherwise create a fresh conversation.
- [ ] Recover only that workflow's durable state, branch artifacts, and review history. Preserve approvals, blockers, review counts, and generation checks.
- [ ] Test `fresh_recovery_loads_only_task_context` and `fresh_session_does_not_reset_gate_state`. Do not claim conversation separation isolates malicious agents.
- [ ] Mark status stale after 60 seconds without a verified Runtime check. Surface blocked jobs and phases through a deduplicated outbox.
- [ ] Post approval-needed, blocked, and PR-ready/delivered summaries to Master chat as well as required project-thread notices.
- [ ] Deduplicate by verified workflow event and destination. Include project/phase and source/artifact links; keep ordinary progress only in project threads.
- [ ] Test `important_event_reaches_master_and_project`, `summary_retry_not_duplicated`, `summary_contains_source_links`, and `ordinary_progress_not_mirrored`.
- [ ] Check container restart with named volumes; two threads in one channel and two independent channels work at the same time. Finish only one delivered thread with explicit `finish` and check that its Herdr sessions are archived.
- [ ] After review, commit: `feat: reconcile runtime state after interruption`.

## Task 12: Portable Operations Contracts and Infrastructure Handoff

**Files:** Create `docs/operations/{containers,private-access,backup-restore,secrets}.md`, `spec/integration/image_contract_spec.rb`; Modify `README.md`, `compose.yml`.

**Interfaces:** Contract documents list ENV, secret file, UID/GID, volumes, ports, healthcheck, and start command per image. Worker/Runtime require the same host/task socket volume.

- [ ] Write `image_contract_spec`: non-root, healthcheck, persistent paths, no Docker/root mounts, no publicly exposed Runtime SSH ports, and version pins matching `.ruby-version`/`.nvmrc`. Assert Alpine Kirei or recorded dependency evidence for Ubuntu; assert the Runtime base follows Task 6 validation.
- [ ] Verify the selected official Team Edition/push artifacts and mobile build provenance, licenses, notices, and permitted dependencies.
- [ ] Run `bundle exec rspec spec/integration/image_contract_spec.rb`; expect missing complete image contracts.
- [ ] Document one PostgreSQL server with separate Kirei/Mattermost databases, roles, migrations, and secrets. Mattermost is an independently upgraded upstream service.
- [ ] Document Team Edition and the existing push proxy as separate services; no inherited Redis/Resque or Rails requirements.
- [ ] Define mobile application IDs, signing and APNs/FCM secret references, delivery/update ownership, and distribution setup as future human tasks.
- [ ] Document two independently built application images and pinned upstream chat/push artifacts. Infrastructure owns production orchestration.
- [ ] Describe private Tailscale/OpenSSH access, Headscale DNS-only through Traefik with trusted TLS; neither Cloudflare Proxy nor Tunnel for Headscale.
- [ ] Document intentional raw terminal access: the human controls agents directly. No owner-side status/approval CLI or Master session is required for attachment.
- [ ] State that terminal input is unsupervised. Kirei's dispatch lock cannot prevent direct input; conflicting changes require review reconciliation.
- [ ] Document ignored `.env`, optional `op://` references, and root/0600 production files in the infrastructure repo. No secret values or login states in images/Git.
- [ ] Create backup/restore matrix: include both PostgreSQL databases/roles, Mattermost attachments and push configuration, Herdr, configuration/audit, and Headscale; exclude clones/worktrees/unpushed work/CLI logins.
- [ ] Use consistent PostgreSQL backups and coordinated Mattermost attachment/configuration restore. Verify relationships and application startup after restore.
- [ ] Hand off daily S3 client-side encryption, external key, 30-day lifecycle, and second-failure alarm to Infra. Explicitly document re-login after restore.
- [ ] Document an image-by-digest example for Production Compose and Hosted Task, including shared socket. Do not present portability as a tested ECS deployment.
- [ ] After review, commit: `docs: define production image and recovery contracts`.

## Task 13: End-to-end Acceptance and Release Evidence

**Files:** Create `spec/integration/phase0_spec.rb`, `bin/acceptance`, `docs/acceptance/phase0.md`; Modify `README.md`, `CHANGELOG.md`, `.agents/changelog.md`.

**Interfaces:** `bin/acceptance local` checks local flows with simulated providers/peer; `bin/acceptance operator` creates a live checklist to complete manually and starts no deployment.

- [ ] Write local full flow: two channels, mobile interview response, spec review/approval, plan review/approval, implementation review, and one PR delivery.
- [ ] Add research flow, optional pushed memory change, peer handoff, and restart between gates. Forbidden approvals/transitions must fail.
- [ ] Run `docker compose run --rm web bundle exec rspec spec/integration/phase0_spec.rb`; expect missing full integration before implementation.
- [ ] Complete full integration and run `bundle exec rspec`, `bundle exec spoom srb tc`, `bundle exec rubocop`, `docker compose config --quiet`, and image builds.
- [ ] Run custom mobile build/unit/device checks and upstream Team Edition compatibility/restore checks. Complete two threaded interviews without crossed replies.
- [ ] Test self-hosted push on our signed iOS/Android builds: background delivery, correct thread deep link, and restored configuration.
- [ ] Record output, commit, image digests, and test environment. Report live checks and simulated checks separately.
- [ ] After separate deployment approval, the operator checks real CLIs, Mattermost mobile access, Tailnet attachment, externally closed SSH port, all service health checks, and encrypted restore.
- [ ] Check every acceptance row below; missing live evidence remains open and must not imply Phase 0 acceptance.
- [ ] After review, commit: `test: document Phase 0 acceptance evidence`.

## Acceptance Matrix for Spec §25

| No. | Responsibility | Required evidence |
| --- | --- | --- |
| 1 | 12/13 + Infra | published OCI digests start in existing infrastructure; separate approval |
| 2 | 1/2/13 | local Compose with upstream Team Edition/push proxy and separate PostgreSQL databases; exit 0 |
| 3 | 12 | same ENV/volume/health contracts, Compose and Hosted Task definition |
| 4 | 6/12/13 + Infra | health of Team Edition, push proxy, DB, Web, Worker, listener, Runtime, Headscale, Tailscale |
| 5–6 | 6/12 | contract test and inspected container UID/mount/capability state |
| 7 | 6/11 | host restart, persistent clones/worktrees/Herdr/Wagglebot/login states |
| 8 | 1/6 | four real CLI starts through pinned Herdr |
| 9–10 | 12/13 + Infra | Tailnet attachment succeeds; external SSH connection test is rejected |
| 11 | 4/9 | Master request from two channels carries the correct source channel |
| 12–13 | 5/6/7 | fresh role sessions; duplicate active-thread start rejected; concurrent same-repo threads use separate worktrees |
| 14–16 | 5 | path/remote checks, three setup actions, one shared service |
| 17–19 | 7 | revision/bot/race negative tests |
| 20–24 | 8 | immutable target/base commits, handshake, Writer lock, queued-message acknowledgement, review handoff, third failure |
| 25–26 | 10 | one branch/PR, no automatic merge |
| 27 | 9/11 | fresh selected-controller session with same configuration and durably reconstructed status |
| 28 | 10/13 | simulated peer and separate Git identity, chat/Git only |
| 29 | 1/12/13 + Infra | encrypted restore of both databases/roles and attachments; logins not restored |
| 30 | 1/4/6/13 + Operator | mobile thread interviews through session-bound Kirei outbox, visible Worker role, authenticated ordinary replies and own-build push/deep links |
| 31 | 10/13 | committed research Markdown with sources and uncertainty |
| 32 | 10/13 + Operator | memory commit and push verified for configured repo identity |

Later provider/MCP integration remains [issue #4](https://github.com/swiknaba/digitaltwin/issues/4), after Phase 2. Mattermost requires no chat-plugin MCP.

## Remaining Validation and Operator Setup

1. **Herdr capability:** Task 1 determines whether four CLIs and the idle handshake are reliable enough. Without proof, do not implement Runtime/review based on assumptions.
2. **Pins and credentials:** Operator provides company config, memory slug, model configuration, and test credentials. Secrets stay outside the plan. Select release pins after checking them.
3. **Mattermost contract:** Validate official Team Edition bot APIs, native threads, authenticated events, and REST reconnect recovery. Validate own mobile builds and self-hosted push. Validate Worker callbacks through Kirei's outbox. Missing secure sender/thread checks block human approval.
4. **Infrastructure:** Production, image publication, Headscale, backup bucket, and restore test are separately authorized work in the infrastructure context. This plan provides contracts only.
5. **Review exclusion:** Kirei prevents prompt dispatch, checks Git, and monitors Herdr. The accepted shared Runtime domain does not protect against intentional direct terminal/filesystem access. Such access blocks/invalidates review and does not count as approved work.

# Digitaltwin Phase 0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A containerized, self-hosted agent fleet delivers code and research results through Campfire with approval bound to their exact revisions.

**Architecture:** Kirei forms a modular Ruby monolith with separate web and worker processes. PostgreSQL stores workflow state and jobs; Herdr controls four CLIs in a shared Non-root runtime container. Campfire and Git are the only interfaces to independent deployments.

**Tech Stack:** Ruby, Kirei, Sorbet, Rack/Puma, Sequel, PostgreSQL, Docker Compose, Herdr, Wagglebot, Codex CLI, Claude Code, OpenCode, Gemini CLI.

**Spec:** [Phase 0 agent fleet specification](../../agent-fleet-architecture-and-review.md).

## Global Constraints

The following values and limits come from the spec; all tasks must comply with them.

- Host target: `Ubuntu 24.04 LTS on AMD64`; no required minimum memory or fleet concurrency limit.
- Prefer Alpine for Kirei and a compatible official Campfire image. Choose the Runtime base after Herdr/CLI validation; record any Ubuntu image requirement.
- Two application images: Kirei and Runtime. Production selects OCI digests; the repository provides development/integration Compose only.
- Exact tool and package versions in manifests; Ruby `4.0.7`; Wagglebot: `Node.js 22.20 or later, npm, and Git`.
- Runtime: `No Docker socket`, `No privileged mode`, `No host root mount`, non-root, required volumes and networks.
- Default workspace: `/workspace/repos`; slug `owner/repository`; one workflow per verified Campfire thread. Multiple threads in a room can work at the same time.
- Bots: `@agent` and `@worker`, configurable. Writer and Reviewer share the Worker bot identity.
- Writer/Reviewer require different underlying providers **and** base model families; default Codex/Claude Code.
- Every project workflow requires a spec, plan, reviews, and human approvals of the exact revisions.
- Three unsuccessful review rounds per gate block; Reviewer changes only the shared review Markdown file.
- One workflow branch, one final PR; no automatic merge and no automatic post-merge synchronization.
- Room members may request ordinary work; configured local/peer bots must never approve or confirm as humans.
- Master: configurable `RoleConfig(cli, provider, model, family)` through Herdr and a local MCP bridge; Gemini CLI is the default. No direct provider API call or login through Campfire.
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
5. Writer changes during review and manipulated callbacks must not move the review snapshot (Task 8).

## Implementation Decisions and Prerequisites

- Generate Kirei bootstrap files with its CLI in an empty staging directory, then copy them into this repository without replacing the existing docs. Add the Gemfile and test setup separately.
- One Ruby codebase provides web, worker, `bin/digitaltwin` callback, and stdio MCP bridge. The Runtime includes the package required by the two small clients.
- PostgreSQL Sequel transactions coordinate gates, session generations, jobs, inbox, and outbox. Network calls run outside short DB locks.
- Reviews reside in `docs/superpowers/reviews/<workflow-uuid>.md`; the UUID stays internal, while ordinary chat messages use project/phase and links.
- New workflow branches are named `digitaltwin/<workflow-uuid>`.
- Approval binds the exact reported artifact commit and expected Markdown path in its Git tree. Review commits do not replace the target commit. Every new artifact-ready report requires renewed review/human approval.
- Messages during review are stored but not sent to the Writer. After review, they are delivered after revision/phase checks.
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
| `db/migrate/001_control_plane.rb` | Projects, workflows, approvals, reviews, sessions, jobs, inbox, outbox, audit, confirmations |
| `app/domains/{jobs,campfire,projects,workflows,reviews,runtime,forge,controller}/` | Typed entities, services, thin controllers, and adapters per domain |
| `bin/{web,worker,digitaltwin,mcp}` | Process entry points and controlled operations |
| `docker/{app,runtime}.Dockerfile`, `compose.yml`, `.dockerignore`, `.env.example` | Two OCI images and local integration |
| `spec/{domains,integration,contracts}/`, `spec/fixtures/` | Unit, PostgreSQL, adapter, and end-to-end evidence |
| `docs/{interfaces,operations,acceptance}/` | Contracts, operations, validation results, infrastructure handoff |
| `AGENTS.md`, `.agents/changelog.md`, `CHANGELOG.md` | Workflow rules and summaries, not a second task queue |
| `README.md` (existing) | Development commands and links |

Shared types in `app/domains/workflows/entities.rb`:

- `Actor(user_id: String, room_id: String, member: Boolean, bot: Boolean)`; from verified Campfire context, never set freely by the model.
- `RoleConfig(cli: String, provider: String, model: String, family: String)`; the Writer/Reviewer pair checks both differences.
- `ArtifactRef(kind: spec|plan|implementation|review, commit: String, path: String?)`; `path` is required for specification, plan, and review Markdown. Implementation uses `path: nil` and targets the entire commit tree.
- `SessionRef(workflow_id: String?, generation: Integer, role: writer|reviewer|controller, pane_id: String, alias: String)`; writer/reviewer require a workflow ID, while controller has none.
- `Outcome(status: accepted|blocked|rejected|confirmation_required, reason: String, links: Array[String])`.
- Workflow states: `spec_writing → spec_review → spec_human_approval → plan_writing → plan_review → plan_human_approval → implementation → implementation_review → pr_ready → done → closed`; additionally `blocked`, `paused`, `cancelled` with the previous state stored.
- `done` means verified delivery of an open PR/research result, not a merge. `closed` follows only explicit thread-specific `@worker finish` and archives Herdr session metadata. Revisions and approvals remain traceable in the audit.

## Task 1: Interface Validation and Version Manifest

**Files:** Create `config/runtime-tools.lock.yml`, `docs/interfaces/{herdr,campfire,cli-startup}.md`, `spec/contracts/{herdr,campfire}_spec.rb`, `spec/fixtures/contracts/`.

**Interfaces:** Produces documented, release-bound Herdr operations for start, prompt, status, stop/archive, and Campfire authentication, membership, webhook ID, post ID, and thread or root post ID.

- [ ] Check selected releases against official documentation and installed artifacts. Record exact versions, origin, and digests/checksums. Select an exact supported Node release ≥22.20.0 for `.nvmrc`.
- [ ] Write contract tests `starts_four_clis`, `writer_settles_after_ready`, `unknown_is_not_idle`, `selected_master_calls_local_mcp`, `campfire_verifies_delivery_and_sender`.
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
- [ ] Define Compose services `web`, `worker`, `postgres`, and later `runtime`; no production routing and no real secrets.
- [ ] Check generated routes register `Router.add_health_routes!`. Run `docker compose config --quiet`, image builds, the boot test, and `bundle exec spoom srb tc`.
- [ ] After review, commit: `build: bootstrap Kirei control plane and local compose`.

## Task 3: Durable Jobs, Inbox, and Outbox

**Files:** Create migration, `app/domains/jobs/{entities,worker,store}.rb`, `app/domains/campfire/outbox.rb`, `spec/domains/jobs_spec.rb`.

**Interfaces:** `Jobs.enqueue(kind: String, payload: Hash, key: String) -> String`; `Jobs.claim(worker_id: String, now: Time) -> Job?`; `complete(id:, lease_token:)`; `retry(id:, lease_token:, error:)`. `Outbox.enqueue(room_id:, body:, key:) -> String`. PostgreSQL jobs dispatch Herdr work, reconciliation, and outbox delivery beyond the webhook request; no Sidekiq or Redis.

- [ ] Write PostgreSQL tests: two workers never claim the same job; a unique key returns one job; an expired lease is retryable; an old lease token cannot complete a job.
- [ ] Add `transaction_rollback_discards_state_and_outbox`, `fifth_failure_blocks`, `effect_succeeded_before_crash`, and `unknown_post_result`: rollback leaves neither state nor outbox row; five failed attempts block; unknown effects do not issue a duplicate network call before reconciliation.
- [ ] Run `bundle exec rspec spec/domains/jobs_spec.rb`; expect missing schema/store.
- [ ] Implement short `FOR UPDATE SKIP LOCKED` claims, lease/heartbeat, bounded retry values, and atomic state change plus outbox. Dispatch a long agent session, then release the job; reconcile completion separately.
- [ ] Check actual PostgreSQL concurrency, retry budget, and dead workers. Treat a crash after an unconfirmed network effect as blocked or uncertain; do not claim exactly-once external delivery.
- [ ] After review, commit: `feat: add durable leased jobs and delivery outbox`.

## Task 4: Campfire Routing and Verified Senders

**Files:** Create `app/domains/campfire/{controller,client,router,actor_resolver}.rb`, `spec/domains/campfire_spec.rb`.

**Interfaces:** `Router.ingest(delivery: VerifiedDelivery) -> Outcome`; `ActorResolver.resolve(room_id:, user_id:) -> Actor`; `VerifiedDelivery` contains verified room, post, and thread or root post identity. Client methods follow Task 1 exactly.

- [ ] Write tests for invalid webhooks, own bots, peer bots, room membership, replay, and duplicate delivery.
- [ ] Check `agent_any_room_preserves_source`, `worker_unactivated_thread_does_not_start`, `worker_thread_routes_without_repeat_mention`, and `worker_thread_cannot_route_to_another_workflow`; ordinary messages expose no internal workflow IDs.
- [ ] Run `bundle exec rspec spec/domains/campfire_spec.rb`; expect missing router.
- [ ] Implement `@agent` to Master and thread-specific `@worker start`/`approve`/`finish`/`cancel`/ordinary message to the active project phase. Activate only the thread root with `@worker start`; route later human thread messages without a repeated mention. Store inbox before dispatch.
- [ ] Check that sender/bot classification comes from Campfire; forged JSON/model fields cannot grant human authority.
- [ ] After review, commit: `feat: route authenticated Campfire mentions`.

## Task 5: Enrollment and Git Workspace

**Files:** Create `app/domains/projects/{enroll,repository_identity,workspace}.rb`, `app/domains/forge/client.rb`, `spec/domains/projects_spec.rb`, `bin/digitaltwin` enrollment.

**Interfaces:** `Projects.enroll(actor: Actor, room_id: String, slug: String, choice: clone|create_private|stop) -> Outcome`; `Workspace.resolve(slug: String) -> String`; `Forge.clone(slug:, destination:)`, `create_private(slug:)`, `read_revision(repo:, commit:)`.

- [ ] Write `valid_slug_maps_path`, `rejects_traversal_and_symlink_escape`, `remote_mismatch_blocks`, `rename_keeps_room_mapping`.
- [ ] For a missing repo, add exactly clone/create-private/stop; create privately only after the selected action, never implicitly.
- [ ] Run `bundle exec rspec spec/domains/projects_spec.rb`; expect missing enrollment services.
- [ ] Implement validated `owner/repository` segments, realpath-based containment checks, and remote identity for HTTPS/SSH. Use argv instead of composed shell strings.
- [ ] Connect chat, MCP, and shell to the same service. Initialize Wagglebot after Task 6 before a project workflow starts.
- [ ] Check with bare Git fixtures whose HEAD explicitly points to main; tests create no GitHub resources.
- [ ] After review, commit: `feat: enroll rooms into verified Git workspaces`.

## Task 6: Non-root Runtime, Herdr, and Wagglebot

**Files:** Create `docker/runtime.Dockerfile`, `config/runtime-entrypoint.sh`, `app/domains/runtime/{herdr_client,sessions,reconcile}.rb`, `spec/{domains/runtime_spec.rb,integration/runtime_spec.rb}`.

**Interfaces:** `Sessions.start(workflow_id: String?, generation:, role:, config: RoleConfig, repo: String?) -> SessionRef`; `send_prompt(session:, text:, dispatch_key:)`; `state(session:) -> idle|done|working|unknown|missing`; `stop(session:)`. Writer/reviewer require non-null workflow ID and repo; controller requires both null and starts in the neutral Runtime home.

- [ ] Write runtime checks: UID ≠ 0, all four CLIs exist, no forbidden mounts/capabilities, socket only on the shared worker volume.
- [ ] Write `unknown_never_completes`, `old_generation_cannot_receive_prompt`, `restart_reconciles_panes` using Task 1 fixtures.
- [ ] Test `Sessions.start` rejects missing workflow ID or repo for writer/reviewer and rejects either value for controller. Check controller working directory is the neutral Runtime home.
- [ ] Run `bundle exec rspec spec/domains/runtime_spec.rb`; expect missing session interface.
- [ ] Implement adapters only against the Task 1 contract. Persist Role→Pane/Alias, session generation, and separate credential areas in the shared Runtime home.
- [ ] Select the Runtime image base after testing pinned Herdr and all CLIs on Alpine. Record the dependency or runtime failure that requires Ubuntu, if any.
- [ ] Build the image with pinned tools, OpenSSH, and Wagglebot. Match `.ruby-version` and `.nvmrc` to image versions. Setup: `connect <company-git-url>`, `update --wagglebot`, per repo `init` and `update`.
- [ ] Provide upgrades only through an explicit operator command. Document interactive provider login; test persistence after container restart.
- [ ] Check `docker compose build runtime` and `docker compose run --rm runtime bin/runtime-smoke`; this new command checks versions/UID and Herdr CLI start. Authenticated provider checks remain separate operator checks.
- [ ] After review, commit: `feat: add persistent Herdr runtime and provisioning`.

## Task 7: Deterministic Workflows and Approvals

**Files:** Create `app/domains/workflows/{entities,machine,approvals,start}.rb`, `spec/domains/workflows_spec.rb`, `AGENTS.md`.

**Interfaces:** `Workflows.start(actor:, project_id:, thread_id:, writer: RoleConfig, reviewer: RoleConfig) -> Outcome`; `finish(actor:, workflow_id:, expected_version:)`; `transition(workflow_id:, event:, expected_version:)`; `Approvals.approve(actor:, workflow_id:, kind:, target_commit:) -> Outcome`.

- [ ] Write table-driven tests for all permitted/forbidden state transitions, spec/plan approval, and the reviewer prerequisite.
- [ ] Add `same_family_across_cli_rejected`, `same_provider_rejected`, `bot_approval_rejected`, `artifact_change_invalidates`, `concurrent_approval_advances_once`, `active_thread_second_start_rejected_without_sessions`, `new_thread_starts_fresh_sessions`, `finish_only_delivered`, `unknown_blocks_finish`, and `cancel_reconciles_before_archive`.
- [ ] Run `bundle exec rspec spec/domains/workflows_spec.rb`; expect missing state machine.
- [ ] Implement state changes with workflow lock/version and audit. Contextual approval binds the presented revision on receipt, not a later moved HEAD.
- [ ] Check approval rejects a missing specification/plan path in the reported commit tree, a changed target commit, and a dirty worktree. Do not add file upload or blob storage.
- [ ] A thread-specific start creates fresh Writer/Reviewer sessions on one branch. Reject a second start in the active thread; another thread can create an independent workflow.
- [ ] Keep pause/resume/cancel/finish orthogonal to approvals. `finish` closes only a delivered workflow after an explicit command and stops/archives its sessions. Resume must not skip gates; idle chat does not end or start anything automatically.
- [ ] Anchor required spec/plan rules in AGENTS.md; technical enforcement stays in Kirei.
- [ ] After review, commit: `feat: enforce revision-bound workflow gates`.

## Task 8: Artifact-ready and Mutually Exclusive Reviews

**Files:** Create `app/domains/reviews/{coordinator,callback,verdict}.rb`, `bin/digitaltwin` callback, `spec/domains/reviews_spec.rb`.

**Interfaces:** `Reviews.ready(session: SessionRef, artifact: ArtifactRef) -> Outcome`; `begin(workflow_id:, target:)`; `finish(session:, review_commit:, verdict: approve|changes_requested) -> Outcome`. CLI: `digitaltwin artifact-ready --kind <kind> --commit <sha>` and `review-ready --commit <sha> --verdict <verdict>`.

- [ ] Write `callback_wrong_session_rejected`, `dirty_writer_blocks`, `writer_working_or_unknown_blocks`, `queued_writer_prompt_not_dispatched`.
- [ ] Add `missing_artifact_path_rejected` and `review_diff_other_file_rejected`. Check the exact target commit tree, Reviewer diff of review file only, append-only sections, real review identities, and block on the third failure.
- [ ] Run `bundle exec rspec spec/domains/reviews_spec.rb`; expect missing coordinator.
- [ ] Stop new Writer dispatches, send transition prompt, verify callback/artifact/commit/cleanliness and settled Herdr state. Persist review lock before Reviewer start.
- [ ] Bind the callback to a short-lived session credential and generation; do not trust model text or Herdr lifecycle events alone.
- [ ] Compare the Reviewer commit with the frozen HEAD; diffs in other files block the round. A section contains provider/model/family, target, findings, verdict, and timestamp.
- [ ] Pass verified review path/commit to Writer; unlock only for the correction phase. Revalidate pending messages and gate revision.
- [ ] Check that all three gates use the same rules and bot/prompt instructions cannot bypass the lock.
- [ ] After review, commit: `feat: coordinate immutable artifact review rounds`.

## Task 9: Master and Local MCP Bridge

**Files:** Create `app/domains/controller/{tools,confirmations,master}.rb`, `bin/mcp`, `spec/domains/controller_spec.rb`.

**Interfaces:** Master `RoleConfig(cli: String, provider: String, model: String, family: String)` reaches `Sessions.start(workflow_id: nil, generation:, role: controller, config:, repo: nil)` unchanged. MCP tools `list_projects`, `list_workflows`, `get_workflow`, `enroll_project`, `start_workflow`, `send_prompt`, `pause_workflow`, `resume_workflow`, `finish_workflow`, `cancel_workflow`, `git_action`, `deployment_action`, `delete_resource`, `change_credentials` receive server-side Actor/Room/Thread context.

- [ ] Write `selected_master_config_reaches_sessions_start`: assert controller role, `workflow_id: nil`, `repo: nil`, and unchanged CLI/provider/model/family. Assert another Task 1-validated CLI/provider reaches the same interface unchanged.
- [ ] Write `room_context_survives_tool_call`, `restart_creates_fresh_session_with_same_config`, `secret_values_never_returned`. Assert restart uses the same config in neutral Runtime home, reconstructs PostgreSQL status, and preserves sender/context checks.
- [ ] Add `bot_cannot_confirm`, `confirmation_replay_rejected`, `changed_parameters_require_confirmation`, `unconfigured_deployment_tool_rejected`.
- [ ] Run `bundle exec rspec spec/domains/controller_spec.rb`; expect missing Master/MCP server.
- [ ] Implement the stdio MCP bridge against the same application services, with no raw shell or credential-read tools.
- [ ] Serialize requests to one logical Master session; pass verified context through a request-bound capability, not freely chosen model parameters.
- [ ] Require a second human confirmation before destructive/irreversible operations. The confirmation window is ten minutes; audit includes the parameter hash, never secret values.
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
- [ ] Implement startup reconciliation from DB, Git, and Herdr; create a fresh Master. Reconstruct work from committed artifacts and existing ignored Superpowers ledger.
- [ ] Mark status stale after 60 seconds without a verified Runtime check. Surface blocked jobs and phases through a deduplicated outbox.
- [ ] Check container restart with named volumes; two threads in one room and two independent rooms work at the same time. Finish only one delivered thread with explicit `finish` and check that its Herdr sessions are archived.
- [ ] After review, commit: `feat: reconcile runtime state after interruption`.

## Task 12: Portable Operations Contracts and Infrastructure Handoff

**Files:** Create `docs/operations/{containers,private-access,backup-restore,secrets}.md`, `spec/integration/image_contract_spec.rb`; Modify `README.md`, `compose.yml`.

**Interfaces:** Contract documents list ENV, secret file, UID/GID, volumes, ports, healthcheck, and start command per image. Worker/Runtime require the same host/task socket volume.

- [ ] Write `image_contract_spec`: non-root, healthcheck, persistent paths, no Docker/root mounts, no publicly exposed Runtime SSH ports, and version pins matching `.ruby-version`/`.nvmrc`. Assert Alpine Kirei or recorded dependency evidence for Ubuntu; assert the Runtime base follows Task 6 validation.
- [ ] Run `bundle exec rspec spec/integration/image_contract_spec.rb`; expect missing complete image contracts.
- [ ] Document PostgreSQL and existing/official Campfire as external services; local Compose can start test dependencies. No production Compose in the app repo.
- [ ] Describe private Tailscale/OpenSSH access, Headscale DNS-only through Traefik with trusted TLS; neither Cloudflare Proxy nor Tunnel for Headscale.
- [ ] Document ignored `.env`, optional `op://` references, and root/0600 production files in the infrastructure repo. No secret values or login states in images/Git.
- [ ] Create backup/restore matrix: include DB, Campfire/attachments, Herdr, configuration/audit, and Headscale; exclude repos/unpushed work/CLI logins.
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
- [ ] Record output, commit, image digests, and test environment. Report live checks and simulated checks separately.
- [ ] After separate deployment approval, the operator checks real CLIs, Campfire mobile access, Tailnet attachment, externally closed SSH port, all service health checks, and encrypted restore.
- [ ] Check every acceptance row below; missing live evidence remains open and must not imply Phase 0 acceptance.
- [ ] After review, commit: `test: document Phase 0 acceptance evidence`.

## Acceptance Matrix for Spec §25

| No. | Responsibility | Required evidence |
| --- | --- | --- |
| 1 | 12/13 + Infra | published OCI digests start in existing infrastructure; separate approval |
| 2 | 2/13 | local Compose integration with exit 0 |
| 3 | 12 | same ENV/volume/health contracts, Compose and Hosted Task definition |
| 4 | 6/12/13 + Infra | health of Campfire, DB, Web, Worker, Runtime, Headscale, Tailscale |
| 5–6 | 6/12 | contract test and inspected container UID/mount/capability state |
| 7 | 6/11 | host restart, persistent repos/Herdr/Wagglebot/login states |
| 8 | 1/6 | four real CLI starts through pinned Herdr |
| 9–10 | 12/13 + Infra | Tailnet attachment succeeds; external SSH connection test is rejected |
| 11 | 4/9 | Master request from two rooms carries the correct source room |
| 12–13 | 6/7 | fresh role sessions; second start in active thread rejected without sessions; new thread starts fresh sessions |
| 14–16 | 5 | path/remote checks, three setup actions, one shared service |
| 17–19 | 7 | revision/bot/race negative tests |
| 20–24 | 8 | immutable review target, handshake, Writer lock, review handoff, third failure |
| 25–26 | 10 | one branch/PR, no automatic merge |
| 27 | 9/11 | fresh selected-controller session with same configuration and durably reconstructed status |
| 28 | 10/13 | simulated peer and separate Git identity, chat/Git only |
| 29 | 12/13 + Infra | encrypted restore of all included services; logins not restored |
| 30 | 13 + Operator | interview completed from mobile Campfire client |
| 31 | 10/13 | committed research Markdown with sources and uncertainty |
| 32 | 10/13 + Operator | memory commit and push verified for configured repo identity |

## Open Decisions

1. **Herdr capability:** Task 1 determines whether four CLIs and the idle handshake are reliable enough. Without proof, do not implement Runtime/review based on assumptions.
2. **Pins and credentials:** Operator provides company config, memory slug, model configuration, and test credentials. Secrets stay outside the plan. Select release pins after checking them.
3. **Campfire contract:** Confirm webhook authentication, membership lookup, and post reconciliation for the deployed release. Missing secure sender checks block human approval.
4. **Infrastructure:** Production, image publication, Headscale, backup bucket, and restore test are separately authorized work in the infrastructure context. This plan provides contracts only.
5. **Review exclusion:** Kirei prevents prompt dispatch, checks Git, and monitors Herdr. The accepted shared Runtime domain does not protect against intentional direct terminal/filesystem access. Such access blocks/invalidates review and does not count as approved work.


## 2026-09-30

- Added a reviewable Phase 0 implementation plan based on spec commit `6129059`, with interface validation gates and all 32 acceptance criteria mapped to evidence.
- Linked the plan from README and prepared an owner-authorized planning branch and draft PR; implementation and deployment remain outside scope.

## 2026-10-01

- Revised Phase 0 routing so each verified Campfire thread owns one workflow and ordinary messages continue in an activated thread without repeat mentions.
- Required explicit thread-scoped `@worker finish` to close a delivered workflow and archive its Herdr session metadata; inactivity cannot close work.
- Aligned the specification and plan with Alpine-preferred images, Kirei CLI bootstrap, Ruby/Node pins, built-in health routes, and PostgreSQL jobs.
- Bound artifact approvals to Git commits and document paths; made Commander configuration selectable and rejected duplicate starts in active threads.
- Removed planning status and local session history from docs and README; aligned the Phase 1 voice reference.
- Added workflow worktrees, an early integration spike, shared-type ordering, incremental schema constraints, and explicit correction/delivery transitions.
- Clarified collaborator authority, raw terminal access, callback limits, review diff scope, queued-message acknowledgements, and durable recovery.
- Planned a maintained Campfire Rails app with thread UI/API and authenticated events; added PostgreSQL search/schema/backup port and upstream maintenance checks.
- Defined separate Campfire and Kirei databases/roles on one PostgreSQL server, three application images, and retained Campfire Redis dependencies pending a backend decision.
- Clarified that Commander operational chat and targeted emergency changes have no coding review cycle; ordinary project workflows retain their gates.
- Recorded the approved Campfire Redis sidecar, private service connectivity, persistence, and restart/restore checks.
- Routed Worker interview/progress replies through a session-bound Kirei callback and durable outbox while retaining visible bot/role identity.
- Defined thread-scoped pause as suppressing new dispatch while preserving current-step completion and callbacks; resume revalidates phase, revision, Runtime, and existing gates.
- Confirmed shared Commander conversational context and operational access across fleet rooms, with separate Commander sessions and private control/runtime data for independent fleets.
- Made Commander-created workflow threads an optional Phase 0 convenience with verified/idempotent association; retained existing-thread starts and added a Phase 1 deferral path.
- Kept detailed updates in project threads and routed important summaries/blockers to configured Commander chat with source links and event/destination deduplication.
- Defined worker sessions as LLM conversations, restricted reuse to the same workflow topic/role/configuration, and scoped fresh recovery to task state while retaining shared Commander fleet context.

## 2026-10-01 — Final peer session policy from review interview

- Commander alone initiates separately managed fleet sessions. Worker/peer requests need human approval and Commander creation; harness-native subordinate agents remain allowed where supported.
- Preserve human thread starts and the authorized Writer/Reviewer review/recovery lifecycle without repeated spawn approvals. Document Kirei bootstrap and the shared Runtime/raw-terminal limits.
- Add a planned versioned peer-handoff contract and tests for authenticated context, replay, recipients, artifact bindings, rejected bot starts, and rejected autonomous chains; no automatic limits replace human approval.
- Reconciled all 16 new review threads and the interview decisions across specification, plan, README, and Phase 1. Checked diff whitespace, Markdown links/fences/tables, 13 tasks, and all 32 acceptance criteria. No system implementation or runtime test claims.

## 2026-10-01 — Worker Linux tool baseline

- Require the lean shell/search/text/file/Git/HTTP/JSON/archive/Python standard-library baseline in the actual Herdr Runtime used by Writer and Reviewer.
- Extend planned Runtime provisioning and executable smoke checks with distro package names, GNU/BusyBox and fd/fdfind distinctions, disposable-script cleanup, and live harness execution checks. Reuse existing Wagglebot/CLI setup.
- Preserve conditional Alpine selection and the Ubuntu host. Compare glibc container fallbacks; Omarchy is a desktop distribution rather than a headless Runtime base. No provisioned runtime or host-package changes are claimed.
- Checked official package/CLI/distro documentation, final diff whitespace, Markdown structure/local links, task count, and unchanged acceptance matrix.

## 2026-10-01 — Approved Mattermost and LiveKit direction

- Replace the planned Campfire server fork/SQLite-to-PostgreSQL port/Redis sidecar with the official unmodified Mattermost Team Edition artifact and external Kirei bot REST/WebSocket integration. Use explicit channel mappings, verified root posts, durable event identities, and reconnect backfill.
- Plan our signed mobile builds and the existing self-hosted Mattermost push proxy/APNs/FCM path, with human-owned enrollment/credentials/distribution and upstream security maintenance. Keep push outside Kirei.
- Distinguish official compiled-server MIT licensing from mixed server-source licensing. Audit exact artifacts, bundled plugins, dependencies, outputs, notices, and branding; exclude commercial components and required Calls/Agents plugins rather than bypass licensing checks.
- Replace Phase 1 voice transport with independent self-hosted LiveKit group calls and AI voice. Require native client/background/device integration checks; preserve existing Commander authority and coding gates.
- Link issue #4 for the post-Phase 2 LiteLLM/MCP direction; add no current-phase rollout or chat-plugin MCP requirement.
- Validate Markdown/local links/tables/fences, 13 tasks, 27 spec sections, all 32 acceptance criteria and matrix coverage, obsolete-path removal, and preservation of existing workflow/runtime/peer policies. This remains documentation only.

## 2026-10-01 — Repository scaffold and parallel ownership

- Add top-level Kirei, Runtime, Mattermost, push-proxy, and mobile folders with purpose, API/configuration boundaries, ownership, and validation gates in each README.
- Add docs/scripts/tests READMEs, root integration-test ownership, repository agent rules, and ignored local secret/build paths. Keep upstream server/proxy configuration separate from application builds.
- Map planned root Kirei/mobile/Docker paths to component folders without moving application source; align the Phase 0 plan's path and command conventions.
- Record official upstream contract references and open Task 1 evidence. No verified pins, CLI/MCP handshake, chat-to-Herdr slice, signed mobile delivery, application boot, or deployment is claimed.
- Reserve root Compose/environment glue for the Kirei foundation/integration owner after startup contracts and artifact pins are verified.

## 2026-10-01 — Verified foundation artifacts and local dependency scaffold

- Publish draft scaffold PR #5 with the original signed commit preserved through GitHub API after direct Git DNS failed.
- Verify Kirei 0.10.0 gem checksum and generate its real CLI scaffold; preserve required Ruby 4.0.7 while recording local generation under 4.0.5.
- Verify Herdr 0.9.3 macOS checksum/version and capture its exact protocol/schema; record Linux provenance without claiming Linux/provider behavior.
- Resolve official Team Edition 11.11.1, push proxy 6.6.0, PostgreSQL 18.6 Alpine, Ruby 4.0.7 Alpine, and mobile release-2.44 identities.
- Add digest-pinned local PostgreSQL/Mattermost Compose, separate-role initializer, safe environment examples, and detailed worker/check handoffs.
- Check Compose configuration, initializer/generated-source syntax, manifest records, schema checksum, and document consistency. Docker daemon is stopped; no applications or provider sessions started.

## 2026-10-01 — Live foundation checks and numbered migration correction

- Start existing Docker Desktop normally and verify disposable PostgreSQL/Mattermost startup, health, database-role connection separation, and Mattermost HTTP ping/version.
- Correct the generated timestamp-based migration tasks to IntegerMigrator/schema_info, positive rollback counts through version zero, and contiguous numbered generation. Preserve the planned 001-006 naming.
- Add four focused RSpec regressions against disposable PostgreSQL, covering migrate/status/idempotency, rollback, invalid steps, and generation. Record local Ruby 4.0.5 fixture execution separately from required Ruby 4.0.7 application startup.
- Remove only the disposable Compose project's resources after checks; leave Docker available. No provider sessions, production credentials/access, or paid calls were created.

## 2026-10-01 — Conceptual component folder names

- Rename component folders to integration-backend, agent-runtime, chat-backend, push-service, and mobile-apps so directory ownership does not depend on implementation technology.
- Update local links, path/branch conventions, mobile ignore rules, component README titles, and future packaging paths; preserve upstream image/API identifiers and source behavior.
- Validate document links, stale-path references, Compose configuration, Ruby/shell syntax, schema/artifact identity, and the relocated live migration regression suite.

## 2026-10-01 — Root integration preparation

- Prepare opt-in backend Compose with agreed UID, port, database/pool settings, migration gate, worker-only Herdr socket volume, and actual process commands.
- Add native Mattermost local-mode health and plugin/marketplace controls; retain the explicit upstream plugin archive audit/removal gap.
- Add disposable dependency acceptance and root configuration tests; record received socket/callback/push contracts and a real roundtrip procedure without provider credentials.
- Verify five root agreement tests, Compose configuration, own-database connections, denied cross-database connections, and Mattermost native health/ping/version. Remove disposable resources; retain live authenticated chat/provider/MCP gates.

## 2026-10-01 — Combined-stack check preparation

- Add concise reasons for root glue, shared docs, scripts, and tests; leave component-owned files untouched.
- Confirm callback generation environment, private base URL, CLI arguments, and HTTP acceptance from the backend owner's standalone client.
- Prepare read-only combined-stack backend health/socket/status checks with an explicit project and Runtime service. No actual combined-stack or provider pass is claimed before reviewed component integration.
- Verify seven root contract/safety checks, Compose configuration, Python syntax, and whitespace. Publication requires the renewed direct approval; no unreviewed component merge occurs here.

## 2026-10-01 — Component handoff wiring preparation

- Inspect fetched component PR handoffs without merging them; prepare local combined Compose for minimal derived chat, hash-checked single-source Runtime callback packaging, private socket/home/workspace volumes, and optional credential-disabled push.
- Add network-free one-shot volume/config setup and callback context staging; leave component directories untouched and the existing dependency default intact pending review clearance.
- Validate combined configuration and root contract tests. Actual image builds, fresh combined boot, authentication/provider roundtrip, and main-default handoff remain unclaimed until reviewed component integration.

## 2026-10-01 — Reviewed chat root default

- Integrate only the explicitly review-cleared chat merge locally; build its minimal derived artifact through root Compose and make it the PostgreSQL/chat default.
- Seed writable UID2000 chat configuration in a network-free one-shot initializer. Keep Runtime volume setup opt-in and push/email disabled.
- Verify root Compose contracts and disposable derived-chat dependency startup/database isolation; retain all authenticated chat/provider and combined-stack gates. Publication remains blocked; no alternate route is used.

## 2026-10-02 — Backend loading conventions

- Remove explicit requires from integration-backend application source and rely on Bundler group loading plus Zeitwerk.
- Remove `require: false` from all Gemfile dependencies and add component rules for typed Ruby, persistence, and checkpoint invariants.
- Record the backend loading boundary in repository memory for future component work.

## 2026-10-01 — Reviewed Runtime root check

- Integrate the review-cleared Runtime merge locally; build only its explicit offline target and verify fresh root volume initialization, native Herdr 0.9.3/protocol22 health, and same-UID mode0600 socket access from a second container.
- Remove all disposable resources; package no callback and start no backend/CLI/provider session. Add a reusable offline Runtime acceptance mode and strict release-bound server-health checks.
- Independently verify the backend owner's frozen formatted callback hash and update root staging enforcement. Keep callback packaging blocked until the matching reviewed Runtime pin update and backend merge.
- Verify 12 root tests, all Compose profiles/configurations, Python syntax, and whitespace; retain publication and full roundtrip blockers.

## 2026-10-01 — Stable combined-test preparation

- Integrate only the approved main baseline containing mobile and the Runtime callback-pin follow-up. Confirm matching root/Runtime SHA256 enforcement without staging unreviewed backend code.
- Verify 12 root tests, all Compose profiles/configurations, Python syntax, and whitespace; keep the checkout clean and stable pending the backend's reviewed merge and independent combined testing.

## 2026-10-01 — Role health correction

- Correct the independent integration review finding: worker/listener now override the backend image's web probe with their role-specific `bin/health` command.
- Add a root regression for both role probes; verify 13 root tests and Compose configuration without merging the pending backend or claiming actual combined startup.

## 2026-10-01 — Credential-free listener gate

- Make the authenticated listener opt-in under `chat-validation`; set its private server URL and explicit validation mode without creating tokens or identities.
- Keep worker validation disabled by default; document separate operator credential/identity wiring and fail-closed startup. Verify the listener is absent from default service selection and 14 root tests pass.

## 2026-10-01 — Reviewed combined baseline

- Integrate only the approved backend main merge locally; independently verify the frozen callback from its source commit and final reviewed backend head.
- Finish authorized Runtime callback source-revision metadata without changing historical PR10 evidence or component behavior. Stage only the hash-checked single-file local build context.
- Verify 14 root tests and all Compose profiles/configurations; freeze the clean combined baseline for independent actual-stack testing. Publication remains blocked and no full acceptance is claimed.

## 2026-10-01 — Tested local core default

- Integrate the independent six-test live combined-stack pass and sanitized evidence locally, preserving all approved main/root changes.
- Promote the exact tested resolved service graph into default Compose; retain old overlay paths as no-op compatibility files and keep authenticated listener/push opt-in.
- Add local `scripts/dev` bootstrap with preserved environment/data, explicit checksum-verified callback staging, and normal Compose build/start. Verify graph equivalence, 15 root tests, shell/Python syntax, and whitespace.
- Require an independent targeted default-entrypoint rerun before treating the promotion as accepted. Publication remains blocked; authenticated chat/provider/MCP/device and full Phase 0 gates remain open.

## 2026-10-02 — Backend domain-only layout

- Move HTTP controllers, DTOs, and errors from `app/controllers/` to `app/domains/orchestration/http/` (`Domains::Orchestration::Http`). Rename `requests/` to `dto/`.
- Rename the coordination domain to `orchestration` (`Domains::Orchestration`), including its spec, bin scripts, and contract paths.
- Verify whole-project Sorbet check passes. Six RSpec failures (migration tasks, projects) also fail on the original commit.
- Rename the `orchestration` domain to `commander` (`Domains::Commander`).
- Rename the `forge` domain to `git_repos` (`Domains::GitRepos`) and the `Projects::Enroll` `forge:` argument to `git_repos:`.
- Add the layered DDD refactor plan `docs/superpowers/plans/2026-10-02-backend-ddd-refactor.md`, and update backend `AGENTS.md` layout rules to match it.

## 2026-10-02

- Removed the backend `config/initializers/database.rb` override of `Kirei::App.raw_db_connection`; `app.rb` now sets `db_global_extensions` (`fiber_concurrency`), pool bounds from `DB_POOL_SIZE`/`DB_POOL_TIMEOUT`, and session timeouts through Kirei 0.11 config. The Gemfile now sources Kirei from its git `main` branch; run `bundle install` and `bundle exec tapioca gem kirei` after swiknaba/kirei#41 merges.
- Replaced the backend `config/initializers/health.rb` JSON heartbeat with `Platform::Heartbeat`, which touches `digitaltwin-<role>.heartbeat` under `HEARTBEAT_DIR` (default `/tmp`); `bin/health` now fails on a missing or stale mtime only. `config/initializers/startup.rb` resolves migrations from `Kirei::App.root`.
- Updated Kirei to git main `84055a2` (fiber-local router env, `PATH_INFO` routing, duck-typed `rack.input`, 400 for bad JSON, `max_request_body_bytes`) and regenerated its RBI. Removed `config/initializers/rack_compatibility.rb`, the `Digitaltwin#call` override, and `spec/contracts/rack_compatibility_spec.rb`; `app.rb` sets `config.max_request_body_bytes = 65_536`. The Falcon integration spec still verifies 400 and 413 end to end.
- Projects, workflows, and sessions now get Kirei human ids (`project_`, `workflow_`, `session_` plus 12 characters) instead of UUIDs; workspace path validation and the approve/route command grammar accept them. Jobs, outbox, requests, operations, and confirmations keep UUIDs. Depends on swiknaba/kirei#43 only for integer-key `create`, which this backend does not call yet.
- Converted `inbox`, `audit`, `callbacks`, `approvals`, `reviews`, `queued_messages`, and `followups` to String human ids (`inbox_`, `audit_`, `callback_`, `approval_`, `review_`, `queued_message_`, `followup_` plus 12 characters) by editing migrations in place. Added `Platform::HumanId` for raw-dataset inserts, `created_at` on `sessions`, `reviews`, and `queued_messages`, `created_at` ordering with `id` tiebreak, and the `recover-followup followup_<id>` grammar.

## 2026-10-03

- Refactored the backend into four Zeitwerk layers: `app/domains/` (bounded contexts with private `Kirei::Model` entities and public `dto/` and `errors/`), `app/services/` (use cases and job handlers), `app/adapters/` (Mattermost, Herdr, git, credential files, HTTP, MCP), and `app/platform/` (jobs, lock, transaction, audit, JSON boundary types). Public services return `Kirei::Services::Result`; `Services::Composition` is the composition root over `Services::Configuration` and `Services::JobHandlers`. `spec/contracts/architecture_boundaries_spec.rb` enforces the layer rules with an empty migration allowlist. The Commander MCP manifest now types `evidence_inbox_ids` items as `"string"`.

## 2026-10-03 — Commander plan and terminology

- Rewrite the first-release Commander plan around visible task goals, bounded work, and completion checks; preserve the approved feature scope.
- Replace old coordinator labels in current product prose and rename the routing/voice document paths; preserve existing operating identifiers and historical evidence.
- Record the remaining application-name audit and require a coordinated, tested migration before feature work. No runtime implementation or dispatch activation is included.

- Add the requested distinction between direct human, Commander-forwarded, and Commander-written worker instructions to the Commander spec and plan. Require backend-owned prompt context, source links, truthful thread labels, unchanged attribution during recovery, and no implied human approval.

## 2026-10-04

- Simplify the Commander plan for an undeployed app: direct naming cleanup, empty-database validation, and no installation transition strategy. Remove the obsolete naming audit and repeated terminology guidance.
- Plan a persistent Commander workspace for base instructions and global learnings, with optional Git sync and separate project memory.

- Complete the Commander application rename in PR26: services, domain values, session role, routes, commands, configuration, jobs, fresh schema, fixtures, and Runtime client contracts. Remove the deferred cleanup task from the plan.

- Add Commander base instructions with simple, medium, and complex model tiers; extend the spec and plan for verified profile selection, human overrides, and independent review diversity.

- Name Opus, Fable, and Sol explicitly in Commander’s complex-task model tier.

## 2026-10-04 — AgentsView usage design

- Add a reviewable Runtime usage specification and implementation plan. They define configurable timezone ranges, distinguish reported zero from unavailable cost, retain a one-tool Commander boundary, and leave the UI disabled by default.
- Change the Runtime base from Alpine 3.23 to the official `node:22.23.2-bookworm-slim` release tag after the verified AgentsView Linux artifact required glibc. Preserve the non-root, persistent-volume, Herdr, four-CLI, Wagglebot, Ruby callback, SSH, and shell-tool contracts. AgentsView packaging itself remains deferred to the post-merge feature PR.
- Pin Runtime client provenance to the retained merged-main revision without changing client bytes or checksums. Add a regression check requiring the source pin to be an ancestor of the checked-out history.

## 2026-10-04 — Herdr startup diagnostic hardening

- Preserve only the verified `agent_pane_busy` socket error code for startup diagnostics. Redact all raw server text and unrecognized codes.
- Verify correlation before reporting a Herdr error. Retry only a rejected `agent_pane_busy` on the same uninitialized pane for two seconds; never retry accepted or launched starts.
- Carry the allowlisted error code as typed `ProtocolViolation` metadata rather than matching display text. Recheck the busy window immediately before another start and sleep no longer than its remaining duration.

## 2026-10-04 — Commander persistent workspace

- Reserve Commander Herdr workspaces at `/workspace/commander`, independently of worker worktrees.
- Create that directory during Runtime startup and retain it through Runtime restart checks.
- Add the persistent Commander memory scaffold. Provider dispatch remains disabled pending live operator evidence.

## 2026-10-04 — Commander workflow status

- Add the request-bound `workflow_status` MCP operation. It filters workflows by authenticated channel access and reports durable workflow, review, approval, artifact, and last-verified session state without asserting live Runtime or delivery success.

## 2026-10-04 — Migration annotation stability

- Synchronize generated entity schema annotations and verify that the clean migration entrypoint does not rewrite them.

## 2026-10-04 — Commander context window

- Extend the bounded readable Commander context from 10 to 50 accessible recent messages for project and task routing.
## 2026-10-04 — Durable Commander memory

- Add bounded, source-attributed global and project Commander memory with optimistic corrections, idempotent requests, scope serialization, and atomic local Markdown rendering.
- Add the durable memory schema and clean-migration coverage. Optional Git synchronization remains unimplemented and disabled because no configured repository or operator credentials are available.

## 2026-10-04 — Commander Hermes architecture

- Revise the Commander specification and implementation plan to use Hermes-native Markdown memory, SQLite history, and skills.
- Plan removal of the Kirei Commander memory subsystem with a forward migration. Preserve Kirei authority for orchestration and verified approvals.
- Use the latest Hermes stable release; upstream publishes dated stable tags, not minor-line tags. Initialize a local Commander Git repository for portable files only; defer automated commits and remote backup.
- Install Hermes in the Runtime final image stage and initialize its persistent Commander workspace as a local repository. Ignore SQLite history, credentials, and runtime state.
- Remove the Kirei Commander-memory implementation and add migration 010 to drop schema-9 memory tables without rewriting migration history.
# 2026-10-04

- Align Commander attribution prompt and tool-response contracts with verified routing metadata.
- Serialize bounded concurrent Commander-memory writes through the scope lock.

## 2026-10-04 — Hermes Commander completion

- Require Hermes for Commander session reservation, dispatch, and recovery; keep Writer and Reviewer profiles independent.
- Initialize Hermes with the request-scoped Kirei MCP allowlist and preserve Commander instructions, native Markdown memory, and skills in local Git.
- Stop migration 010 when legacy Commander memory has data. Require export or explicit disposal before removal.
- Add typed reversible-migration DSL support and deterministic Runtime persistence, Git-ignore, and backend migration coverage.

## 2026-10-04 — Wagglebot reference setup

- Reference Wagglebot's shared worker setup from Commander documentation.
- Keep Commander role instructions and native Hermes state local until Wagglebot supports Hermes provisioning.
- Configure Hermes to read the provisioned shared library at `/home/runtime/.agents/skills`, with deterministic Runtime image coverage.
- Hash underscore-bearing Kirei session aliases before starting Herdr, whose agent names accept hyphens but not underscores.
- Keep the Wagglebot shared-worker baseline product-agnostic; Commander-local guidance now uses only its supplied coordination tools rather than backend implementation names.
- Forward the approved optional company subdirectory through `runtime-provision connect`. Keep the Runtime pin at 0.3.0 until a Wagglebot release fixes its own pinned-runtime install path.
- Remove the legacy tracked Commander Markdown-memory mirror; Hermes-native profile memory is the Commander knowledge source. Keep project `.agents/memory.md` only as task-scoped repository context.

## 2026-10-05 — Herdr accepted-start readiness

- Retry a redacted transient `agent.get` rejection while polling an already accepted Herdr start. Never repeat the start effect; retain the readiness deadline and fail-closed behavior.

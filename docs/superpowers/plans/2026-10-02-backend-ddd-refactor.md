# Integration Backend DDD Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure `integration-backend/app` into layered DDD with private entities, public DTOs, Kirei persistence, and Kirei `Result` returns, without changing observable behavior.

**Architecture:** Four Zeitwerk layers under `app/`: `domains/` (bounded contexts that own tables and invariants), `services/` (cross-domain use cases and job handlers), `adapters/` (vendor and transport translation), `platform/` (jobs, lock, audit). Each task migrates a set of tables end to end, so no raw table access to those tables remains anywhere after that task. An architecture spec enforces the rules. Its allowlist shrinks with each task and is empty at the end.

**Tech Stack:** Ruby 4.0, Kirei 0.10.0 (`Kirei::Model`, `Kirei::Domain::{Entity,ValueObject}`, `Kirei::Services::Result`, `Kirei::Errors::JsonApiError`), Sorbet (`# typed: strict`), Sequel/PostgreSQL, Zeitwerk, RSpec.

**Spec:** The approved layout and rules in the 2026-10-02 session decisions, restated in "Global Constraints" below. The behavior specification is `docs/superpowers/plans/2026-09-30-digitaltwin-phase-0.md`. The existing RSpec suite is the behavioral oracle.

## Global Constraints

- Behavior is unchanged. This includes HTTP wire bodies and status codes, MCP tool names and schemas, job kind strings, dispatch keys, outbox keys, audit event keys, and DB schema. No migration is added.
- Baseline: `bundle exec spoom srb tc` is clean. `bundle exec rspec` reports exactly the 6 baseline failures: `projects_spec.rb:31`, `clean_migration_spec.rb:9`, and `db_tasks_spec.rb:79,90,104,114`. This baseline holds after every task.
- Run tests with `DATABASE_URL=postgres://localhost/digitaltwin_backend_test`.
- Every Ruby file:
  - Has `# typed: strict` and `# frozen_string_literal: true`.
  - Contains one concrete class.
  - Uses double quotes.
  - Gives every method a `sig`.
- Do not use `T.untyped`, `T.unsafe`, `T.cast`, `returns(Object)`, or a broad `T::Hash[..., Object]` in signatures. The only permitted hash types are listed under "Boundary types" below.
- No code under `app/` uses `@db[:table]`, `db[:table]`, `Kirei::App.raw_db_connection`, `Sequel.lit`, or an injected `Sequel::Database`. Persistence goes through `Kirei::Model` class APIs: `create`, `find_by`, `where`, `query`, `resolve`, `resolve_first`, `db.transaction`, `#update`, `#delete`. `Model.query` returns a Kirei-owned dataset. Use it for `for_update`, `insert_conflict`, `max`, joins, and multi-row `update`, and only inside the owning domain.
  - Exception: `Platform::Lock` uses `pg_try_advisory_lock`. Kirei has no API for advisory locks. Document this in its file comment.
- Entities:
  - Location: `app/domains/<ctx>/entities/<name>.rb`, or `app/platform/<ctx>/entities/`.
  - Shape: `T::Struct` that includes `Kirei::Model`, plus `Kirei::Domain::Entity` when the table has an `id`. Keep the schema-info header comment.
  - Type text status columns as `T::Enum` props. Type JSONB columns as nested `T::Struct` props. Kirei serializes both through `serialize` and `from_hash`.
  - Nothing outside the owning context references an entity.
- DTOs:
  - Location: `<layer>/<ctx>/dto/<name>.rb`.
  - Shape: `T::Struct` that includes `Kirei::Domain::ValueObject`, with `const` props only. Enums are `T::Enum` in `dto/`.
  - DTOs are the only data types other contexts reference.
- Results:
  - Public service methods that have expected failures return `Kirei::Services::Result[Dto::X]`.
  - A failure is `Kirei::Errors::JsonApiError.new(code: <Ctx>::Dto::ErrorCode::Y.serialize, detail: "...")`. Build it through `Platform::Failure.call(code:, detail:)`.
  - Each context has one `dto/error_code.rb` `T::Enum`.
  - Expected business failures never raise. Raise only for genuine IO, DB, and lease failures, and for broken invariants.
  - The current `ArgumentError` messages become the `detail` text. Specs that assert on them assert on `result.errors.first.detail` instead.
- Services:
  - Stateless. Collaborators are injected through `initialize`, and the public entry is `call`.
  - Wrap `call` bodies in `Kirei::Services::Runner.call(self.class.name.to_s) { ... }` for metrics.
- Dependency rules (enforced by Task 1's spec):

  | Layer | May reference |
  |---|---|
  | `Platform::*` | Kirei, stdlib, gems |
  | `Adapters::<X>` | `Platform`, `Domains::*::Dto` |
  | `Domains::<X>` | its own internals, `Platform`, `Domains::<Y>::Dto` |
  | `Services::*` | anything except `Domains::*::Entities` and `Platform::*::Entities` |
  | `Adapters::Http`, `Adapters::Mcp` | `Services`, any `Dto` |

  Domains never reference `Adapters` or `Services`.
- Boundary types (the only allowed hashes):
  - `Platform::Json::Scalars = T.type_alias { T::Hash[String, T.any(String, Integer, T::Boolean, NilClass)] }`. Use it for job payload and audit details storage. Consumers convert it with `<Struct>.from_hash(hash, true)`.
  - `Adapters::Mattermost::Client::JsonObject` and `Adapters::Herdr::Client::JsonObject`. These are private to their clients and translated into DTOs before they are returned.
  - HTTP and MCP request parsing in `Adapters::Http` and `Adapters::Mcp`.
- Inbox IDs are `Integer` everywhere. Adapters parse string forms at the boundary. Delete `T.any(Integer, String)` aliases.
- `Domains::Orchestration` is renamed to `Domains::Commander` before Task 1. The Commander drives the fleet, after Commander Shepard in Mass Effect.
- Record changes in `.agents/changelog.md` and update `integration-backend/AGENTS.md` "Layout" in Task 10.

## Target File Map

```
app/platform/
  json/scalars.rb                      # Platform::Json::Scalars alias holder (module)
  failure.rb                           # Platform::Failure.call(code: T::Enum, detail: String) -> T::Array[Kirei::Errors::JsonApiError]
  lock.rb, lock/busy.rb                # Platform::Lock#call(key) { }, raises Lock::Busy
  audit/log.rb, audit/entities/entry.rb, audit/dto/receipt.rb
  jobs/store.rb, jobs/worker.rb, jobs/lease.rb, jobs/payload.rb (interface), jobs/handler.rb (interface)
  jobs/entities/job.rb
  jobs/dto/{job_kind,job_status,claimed_job,job_snapshot,decision,decision_action}.rb
app/adapters/
  mattermost/client.rb, mattermost/api.rb, mattermost/errors/request_failed.rb
  mattermost/dto/{post,channel,user,channel_member,new_post,history_page}.rb
  herdr/client.rb, herdr/dto/{pane,pane_summary,agent_session,agent_status,workspace,launch_spec}.rb
  git/{repositories,revision,evidence,worktrees}.rb, git/errors/operation_failed.rb, git/dto/*.rb
  credentials/file_store.rb            # session/request token files (0600, EXCL, symlink-safe)
  http/{base,callbacks,commander}.rb, http/dto/*.rb, http/errors/missing_authorization.rb
  mcp/{server,http_tools}.rb
app/domains/
  messaging/   inbox, outbox, chat_checkpoints
  projects/    projects
  workflows/   workflows, workflow_requests, approvals, queued_messages
  sessions/    sessions, session_operations, callbacks
  reviews/     reviews
  commander/    commander_requests, followups, confirmations, conversation_bindings
app/services/
  configuration.rb                     # typed ENV snapshot (T::Struct), loaded once
  composition.rb                       # composition root (old Commander::Services.from_env)
  job_handlers.rb                      # JobKind -> Platform::Jobs::Handler registry
  commands/parser.rb, commands/dto/*.rb # chat command grammar -> typed command DTOs
  inbound/{record_delivery,chat_listener,history_recovery}.rb
  outbound/deliver_outbox.rb
  projects/enroll.rb
  workflows/{request_start,provision,reconcile_start,dispatch_phase_prompt,control,advance_approval,approve_current,start_existing}.rb
  sessions/{execute_operation,renew,reconcile_operation,stop_workflow_sessions,bootstrap_commander,post_worker_chat}.rb
  reviews/{artifact_ready,review_finished,dispatch_review,release_queued,queue_callback}.rb
  commander/{ingest_prompt,dispatch,recover,reply,route_followup,deliver_followup,reconcile_followup,record_approval,tools}.rb
```

Each `services/*` file is one class with `call`. A use case that is also a job handler includes `Platform::Jobs::Handler`. Each context folder has a `README.md` of at most 6 lines that states what it owns and its public API.

## Review Focus

1. Duplicate and replayed inputs, such as the same inbox post, dispatch key, outbox key, or callback key with changed content. Expect the same idempotent result or the same rejection as today. Task 2 and Task 4 specs pin this.
2. An expired or lost job lease during an external effect. The job moves to `uncertain` and is not retried. Task 2 pins `Lease#begin_effect` returning false after expiry.
3. A JSONB column read back through `from_hash`, such as `artifacts`, `role_configurations`, `runtime_identity`, or `evidence`, when keys are missing or extra. Resolve strictly and fail closed. Tasks 6, 7 and 9 each add a round-trip spec with a malformed stored row.
4. Recovery commands (`recover-start`, `recover-session`, `recover-followup`, `recover-commander`) from a non-original human. Expect a rejection with no state change. Task 3's parser specs and the existing commander specs pin this.
5. A stale `expected_version` or a concurrently archived workflow. Expect a typed `VersionChanged` or `Inactive` failure with no partial write. Task 6 pins this.

---

### Task 1: Architecture guardrails

**Files:**
- Create: `integration-backend/spec/contracts/architecture_boundaries_spec.rb`, `integration-backend/spec/contracts/architecture_allowlist.yml`
- Create: `integration-backend/app/platform/failure.rb`, `integration-backend/app/platform/json/scalars.rb`
- Create: `integration-backend/app/{domains,services,adapters,platform}/README.md`

**Interfaces:**
- Produces:
  - `Platform::Failure.call(code: T::Enum, detail: String) -> T::Array[Kirei::Errors::JsonApiError]`
  - `Platform::Json::Scalars` (type alias)
  - The allowlist format: one YAML key per rule, each holding a list of repo-relative files that still violate that rule.

- [ ] **Step 1: Write the spec.** It statically scans `app/**/*.rb` with `File.read` and regexes, with one `it` per rule:
  - `forbids raw table access`: matches `/\b(?:@?db|raw_db_connection)\[:/` and `Sequel.lit`.
  - `forbids broad signatures`: matches `returns(Object)`, `T::Hash[Symbol, Object]`, `T::Hash[String, Object]`, `T.untyped`, `T.unsafe`.
  - `keeps entities private`: a reference `Domains::(\w+)::Entities` in a file outside `app/domains/<snake(\1)>/`.
  - `enforces layer dependencies`: applies the table in Global Constraints. It derives the file's layer and context from its path and matches `\b(Domains|Services|Adapters|Platform)::(\w+)` references.
  - Each rule fails with the list of offending `file:line` entries that are not allowlisted. It also fails when an allowlisted file no longer violates its rule, so the allowlist cannot go stale.
- [ ] **Step 2: Run it.** Command: `bundle exec rspec spec/contracts/architecture_boundaries_spec.rb`. Expected: FAIL, listing current violations.
- [ ] **Step 3: Generate the allowlist.** Use the failure output to fill `architecture_allowlist.yml` with the current violators. Then add `Platform::Failure` and `Platform::Json::Scalars`, and the four layer READMEs. Each README states its layer rule from the table.
- [ ] **Step 4: Verify.** Command: `bundle exec rspec spec/contracts/architecture_boundaries_spec.rb && bundle exec spoom srb tc`. Expected: PASS and no type errors. Full suite at baseline.
- [ ] **Step 5: Commit.** Message: `chore: add backend architecture boundary checks`.

### Task 2: Platform — jobs, lock, audit

**Files:**
- Move and rewrite: `app/domains/jobs/*` to `app/platform/jobs/*` (`job.rb` becomes `entities/job.rb`); `app/domains/workflows/lock.rb` to `app/platform/lock.rb`.
- Create: the `app/platform/audit/*` files and the remaining `app/platform/jobs/*` files from the file map.
- Modify: every `handler.call(job, store)` implementer and every `Jobs::Store.new.enqueue` caller, plus every `@db[:jobs]` and `@db[:audit]` access in all files.
- Test: `spec/platform/jobs_spec.rb` (moved from `spec/domains/jobs_spec.rb`), `spec/platform/audit_spec.rb`.

**Interfaces:**
- Produces:
  - `Platform::Jobs::Dto::JobKind < T::Enum`. Its values are exactly: `commander.prompt`, `commander.dispatch`, `commander.control`, `workflow.prompt`, `workflow.start`, `workflow.approve`, `workflow.pause`, `workflow.resume`, `workflow.finish`, `workflow.cancel`, `workflow.provision`, `workflow.phase_prompt`, `session.start`, `session.stop`, `session.renew`, `session.followup`, `review.prompt`, `review.release`, `review.callback`, `mattermost.post`.
  - `Platform::Jobs::Dto::JobStatus < T::Enum` with `pending running complete blocked uncertain`.
  - `module Platform::Jobs::Payload` (interface). Abstract methods: `job_kind -> Dto::JobKind` and `dispatch_key -> String`. Implementers are `T::Struct`s whose props are only `String`, `Integer`, `T::Boolean`, or nilable versions of these.
  - `Platform::Jobs::Store#enqueue(payload: Payload, available_at: Time = Time.now) -> String`. It raises `Platform::Jobs::Errors::DispatchKeyReused` when the key exists with changed content.
  - `Platform::Jobs::Store#claim(worker_id: String, now: Time) -> T.nilable(Dto::ClaimedJob)`.
  - `Platform::Jobs::Store#snapshot(dispatch_key: String) -> T.nilable(Dto::JobSnapshot)`, where the snapshot has `id`, `status`, and `lease_expires_at`.
  - `Platform::Jobs::Store#close_reconciled(id: String) -> void` sets status to `complete` and clears the lease.
  - `Platform::Jobs::Store#unstarted?(kind: Dto::JobKind, field: String, value: String) -> T::Boolean`. It is true when a `pending` or `blocked` job of that kind exists with `effect_started_at IS NULL` and `payload[field] == value`.
  - `Platform::Jobs::Dto::ClaimedJob`: `id`, `kind: JobKind`, `payload: Platform::Json::Scalars`, `attempts`, `lease: Platform::Jobs::Lease`.
  - `Platform::Jobs::Lease#begin_effect -> T::Boolean`. `Lease#heartbeat -> T::Boolean` is used only by the worker.
  - `module Platform::Jobs::Handler` (interface): abstract `call(job: Dto::ClaimedJob) -> Dto::Decision`.
  - `Dto::Decision`: `action: DecisionAction` (one of `complete`, `defer`, `block`) and `reason: T.nilable(String)`. The worker applies the store transition. Exceptions still go to `retry`.
  - `Platform::Lock#call[R](key: String, &blk: -> R) -> R` raises `Platform::Lock::Busy`.
  - `Platform::Audit::Log#record(event_key: String, action: String, details: T::Struct) -> void`.
  - `Platform::Audit::Log#find(event_key: String) -> T.nilable(Dto::Receipt)`, where `Receipt` has `action` and `details: Platform::Json::Scalars`.
- Consumes: Task 1 guardrails.

- [ ] **Step 1: Write the failing specs.** Move the `jobs_spec.rb` assertions to the new API, plus these new examples:
  - `enqueue is idempotent per dispatch key and rejects changed payload`
  - `begin_effect returns false after lease expiry`
  - `handler decisions map to complete/defer/block`
  - `unstarted? matches only effect-free pending or blocked jobs`
  - `audit record is unique per event key`
- [ ] **Step 2: Run them.** Command: `bundle exec rspec spec/platform`. Expected: FAIL with uninitialized `Platform::Jobs`.
- [ ] **Step 3: Implement the platform files.** Then convert each current handler:
  - Define its payload struct in the owning context's `dto/`, named `<Thing>Job`. For example, `Domains::Workflows::Dto::PhasePromptJob(workflow_id, version)` with dispatch key `"workflow:phase:#{id}:#{version}"`.
  - Each handler parses its payload with `from_hash(job.payload, true)` and returns a `Decision` instead of calling `store.block` or `store.defer`.
  - Handlers that start effects call `job.lease.begin_effect`.
  - Keep the handler classes where they are. Task 10 moves registration.
  - Replace `@db[:audit]` and `@db[:jobs]` everywhere with `Audit::Log` and `Store`.
  - Delete `Commander::Services::LegacyJob` and `RoutedJob`.
- [ ] **Step 4: Verify.** Commands: `bundle exec spoom srb tc`, `bundle exec rspec`, and the architecture spec. Expected: clean types, the baseline failures, and allowlist entries for jobs, audit and lock removed.
- [ ] **Step 5: Commit.** Message: `refactor: move jobs, lock, and audit to platform`.

### Task 3: Adapters and command parsing

**Files:**
- Move: `app/domains/mattermost/{client,client/*}` to `app/adapters/mattermost/`; `app/domains/sessions/herdr*` to `app/adapters/herdr/`.
- Move: `app/domains/git_repos/*`, `app/domains/commander/git_revision.rb`, `app/domains/reviews/git_evidence.rb`, and the git subprocess methods of `app/domains/projects/workspace.rb` to `app/adapters/git/`.
- Move: `app/domains/commander/http/*` to `app/adapters/http/`; `app/domains/commander/{mcp,http_tools}.rb` to `app/adapters/mcp/`.
- Move: the `listener.rb`, `reconcile.rb`, `delivery.rb` and `actor_resolver.rb` process logic to `app/services/inbound/*` and `app/services/outbound/deliver_outbox.rb`. These still use raw tables until Task 4.
- Create: `app/adapters/credentials/file_store.rb`, `app/services/commands/parser.rb`, `app/services/commands/dto/*`.
- Modify: `config/routes.rb`, `bin/mcp`, `bin/worker`, `bin/chat-listener`, and `../agent-runtime/contracts/kirei-clients.json` source paths.
- Test: move `herdr_spec.rb`, `git_evidence_spec.rb` and `git_revision_spec.rb` to `spec/adapters/`, and add `spec/services/commands/parser_spec.rb`.

**Interfaces:**
- Produces:
  - `Adapters::Mattermost::Api` methods:
    - `post(id) -> Dto::Post`
    - `channel(id) -> Dto::Channel`
    - `user(id) -> Dto::User`
    - `me -> Dto::User`
    - `member(channel_id:, user_id:) -> T.nilable(Dto::ChannelMember)`, which returns nil on 404 or `RequestFailed`
    - `create_post(Dto::NewPost) -> Dto::Post`
    - `channel_history(channel_id:, since:, page:) -> Dto::HistoryPage`
  - The `Dto::Post` fields are `id`, `channel_id`, `user_id`, `root_id`, `message`, `create_at`, `update_at`, `delete_at`, and `props: T::Hash[String, String]`. Only `digitaltwin_*` string props are kept.
  - `Adapters::Herdr::Client` methods:
    - `pane(id) -> Dto::Pane`
    - `prompt(pane_id:, text:) -> void`
    - `start(pane_id:, name:, launch: Dto::LaunchSpec) -> Dto::Pane`
    - `create_workspace(cwd: T.nilable(String), label:, env: T::Hash[String, String]) -> Dto::Workspace`
    - `panes -> T::Array[Dto::PaneSummary]`
    - `close(pane_id:) -> void`
  - Herdr DTOs:
    - `Dto::AgentStatus < T::Enum` has `idle working done unknown`, plus any other values the captured Herdr schema already handles.
    - `Dto::Pane` has `pane_id`, `name`, `cwd`, `agent`, `agent_status`, `agent_session: T.nilable(Dto::AgentSession)`, `interactive_ready`, and `launch_pending`.
  - Git adapters:
    - `Adapters::Git::Repositories#clone(slug:, destination:)` and `#create_private(slug:)`.
    - `Adapters::Git::Revision#call(worktree_path:) -> String`.
    - `Adapters::Git::Evidence` keeps today's checks with typed inputs: a `Dto::WorktreeRef(worktree_path, branch)` and commit strings in place of workflow hashes.
    - `Adapters::Git::Worktrees` with `#top_level`, `#remote`, `#add`, `#branch`, `#common_dir`.
  - `Adapters::Credentials::FileStore#write(name:, token:) -> String path`, `#read(name:) -> String`, `#delete(name:) -> void`.
  - `Services::Commands::Parser#call(body: String, agent_handle:, worker_handle:) -> T.nilable(Commands::Dto::Command)`.
    - `Command` is a union of `T::Struct`s: `RecoverStart(request_id, thread_id)`, `RecoverSession(operation_id, pane_id)`, `RecoverFollowup(followup_id: Integer, outcome: FollowupOutcome)`, `RecoverCommander(request_id)`, `Approve(workflow_id, gate, commit)`, `Route(workflow_id, text)`, `WorkerCommand(action: WorkerAction)`.
    - `WorkerAction` has `start approve pause resume finish cancel`.
    - The parser holds every regex now in `commander/services.rb`, `routing.rb` and `mattermost/router.rb`, unchanged.
- Consumes: Task 2 platform.

- [ ] **Step 1: Write the failing parser specs.** One example per command with today's exact accepted strings. Rejections must include a near-miss: a trailing space, an uppercase hex commit, a wrong handle, and a 39-character commit.
- [ ] **Step 2: Run them.** Command: `bundle exec rspec spec/services/commands`. Expected: FAIL.
- [ ] **Step 3: Implement.**
  - Move files and update callers.
  - Callers receive DTOs, so translate `["agent_status"]`-style reads to DTO fields.
  - HTTP adapters keep identical JSON bodies and status codes.
  - Replace inline regexes with parser calls.
- [ ] **Step 4: Verify.** Run `srb tc`, the full RSpec suite and the architecture spec. Expected: baseline, with the adapter files gone from the allowlist.
- [ ] **Step 5: Commit.** Message: `refactor: extract adapters and command parser`.

### Task 4: Messaging domain (inbox, outbox, chat_checkpoints)

**Files:**
- Create in `app/domains/messaging/`:
  - `entities/{inbox_entry,outbox_message,chat_checkpoint}.rb`
  - `dto/{verified_delivery,verified_actor,event_kind,inbox_record,outgoing_message,outbox_item,outbox_status,bot,speaker_role,recorded_delivery,outbox_post_job,error_code}.rb`
  - `{record_delivery,inbox,verify_human_source,outbox,checkpoints}.rb`
  - `delivery_verifier.rb` and `membership_check.rb`, both interfaces.
- Delete: `app/domains/mattermost/` (all of it), `Commander::Source`, `Workflows::Entities::Actor`, and `Workflows::Entities::Outcome`.
- Modify: `Services::Inbound::*` and `Services::Outbound::DeliverOutbox`. `Adapters::Mattermost` gains `DeliveryVerifier`, which implements `Messaging::DeliveryVerifier` from the old actor resolver. Update every `Outbox.new.enqueue`, `@db[:inbox]` and `@db[:outbox]` caller.
- Test: `spec/domains/messaging/*_spec.rb`; adapt `mattermost_spec.rb`, `reconcile_spec.rb` and `outbox_delivery_spec.rb`.

**Interfaces:**
- Produces:
  - `Messaging::Dto::VerifiedDelivery`: `channel_id`, `post_id`, `thread_id`, `actor: VerifiedActor`, `event_kind: EventKind`, `post_revision: Integer`, `body`, `root_post: T::Boolean`.
  - `Messaging::Dto::VerifiedActor`: `user_id`, `channel_id`, `member`, `bot`.
  - `Messaging::Dto::OutgoingMessage`: `channel_id`, `thread_id: T.nilable(String)`, `bot: Bot` (`agent` or `worker`), `role: SpeakerRole` (`commander`, `writer` or `reviewer`), `body`, `key`.
  - `module Messaging::DeliveryVerifier`: abstract `delivery(post_id:, channel_id:, event_kind: EventKind) -> Dto::VerifiedDelivery`.
  - `module Messaging::MembershipCheck`: abstract `member?(channel_id:, user_id:) -> T::Boolean`.
  - `Messaging::RecordDelivery#call(delivery:) -> Result[Dto::RecordedDelivery]`, where the payload is `inbox_id: T.nilable(Integer)` and `duplicate: T::Boolean`.
  - `Messaging::Inbox` methods:
    - `#find(id: Integer) -> T.nilable(Dto::InboxRecord)`
    - `#recent(since: Time, limit: Integer) -> T::Array[Dto::InboxRecord]`
    - `#lock(id: Integer) -> void`, which takes `FOR UPDATE` inside the caller's transaction
  - `Messaging::VerifyHumanSource#call(inbox_id: Integer, destination: T.nilable(String) = nil) -> Result[Dto::VerifiedDelivery]`. Its error codes are `MissingSource`, `SourceChanged` and `DestinationMembershipRequired`.
  - `Messaging::Outbox#enqueue(message: Dto::OutgoingMessage) -> Result[String]`. It enqueues `OutboxPostJob(outbox_id)` with key `"outbox:#{id}"`. Error codes: `KeyReused` and `WorkerMessageRequiresThreadAndRole`.
  - `Messaging::Outbox#item(id:) -> T.nilable(Dto::OutboxItem)`, `#mark_delivered(id:, remote_post_id:)`, `#mark_uncertain(id:)`, `#mark_blocked(id:)`.
  - `Messaging::Checkpoints#revision(channel_id:) -> Integer`, `#advance(channel_id:, revision:) -> void`, `#quarantine(channel_id:, post_id:, reason:) -> void`. Quarantine writes through `Audit::Log`, as today.
  - The current router classification moves to `Services::Inbound::RecordDelivery#call(delivery:) -> Result[Services::Inbound::Dto::IngestOutcome]`. `IngestOutcome` has `status: IngestStatus` (`accepted`, `rejected` or `blocked`) and `reason`. It uses `Workflows` reads through the Task 6 API. Until Task 6, it uses the existing `Domains::Workflows::Workflow` model, which stays on the allowlist.
- Consumes: Tasks 2 and 3.

- [ ] **Step 1: Write the failing specs.**
  - `record_delivery dedups by channel/post/kind/revision`
  - `verify_human_source fails SourceChanged when body or revision differs`
  - `outbox enqueue rejects changed content under same key`
  - `worker message without thread fails`
  - `checkpoint advances only forward`
- [ ] **Step 2: Run them.** Command: `bundle exec rspec spec/domains/messaging`. Expected: FAIL.
- [ ] **Step 3: Implement.**
  - Replace the old interfaces, and convert every former `ArgumentError` path in these files into a `Result` failure.
  - Callers that raised on failure now branch on `result.failed?`. Job handlers turn a failure into `Decision(block, detail)` when the old code blocked. They raise `Services::Errors::StepFailed`, a new file, when the old code raised, which keeps today's retry semantics.
- [ ] **Step 4: Verify.** Expected: baseline, with the messaging tables gone from the allowlist.
- [ ] **Step 5: Commit.** Message: `refactor: add messaging domain`.

### Task 5: Projects domain

**Files:**
- Create in `app/domains/projects/`: `entities/project.rb`, `dto/{project,enroll_choice,enrollment,error_code}.rb`, `{directory,register,workspace_paths}.rb`.
- Move: `Projects::Enroll` to `app/services/projects/enroll.rb`.
- Delete: `projects/workspace.rb`, which is split into `WorkspacePaths` (pure path rules) and `Adapters::Git::Worktrees`.
- Modify: every `@db[:projects]` caller. That includes `Tools`, `StartExisting` and `Provision`.

**Interfaces:**
- Produces:
  - `Projects::Directory` methods: `#find(id:) -> T.nilable(Dto::Project)`, `#for_channel(channel_id:) -> T.nilable(Dto::Project)`, `#all -> T::Array[Dto::Project]`.
  - `Projects::Register#call(channel_id:, slug:, remote_identity:, workspace:) -> Result[Dto::Project]`.
  - `Projects::WorkspacePaths` methods: `#repository(slug:) -> String`, `#worktree(slug:, workflow_id:) -> String`, `#contained!(root:, path:) -> String`.
  - `Services::Projects::Enroll#call(actor: Messaging::Dto::VerifiedActor, channel_id:, slug:, choice: Dto::EnrollChoice) -> Result[Dto::Enrollment]`.
- [ ] **Step 1: Write the failing tests.** Adapt `projects_spec.rb` to the new API. Keep line 31 failing exactly as on baseline. Add `register rejects duplicate channel/slug as a failure result`.
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Verify.** Expected: baseline.
- [ ] **Step 5: Commit.** Message: `refactor: add projects domain`.

### Task 6: Workflows domain

**Files:**
- Create in `app/domains/workflows/`:
  - `entities/{workflow,workflow_request,approval,queued_message}.rb`
  - `dto/{phase,gate,control_action,request_state,artifact_ref,artifact_set,role_config,role_assignments,workflow_view,request_view,approval_view,phase_prompt_job,provision_job,error_code}.rb`
  - `{catalog,transitions,requests,approvals,queued_messages,policy}.rb`
- Move: `workflows/coordinator.rb` and `workflows/provision.rb` to `app/services/workflows/*`, split per the file map. Move `Commander::Services#{control_existing,approve_existing,start_existing,commander_control}` there too.
- Delete: `workflows/entities/{session_ref,artifact_ref}.rb`, which are unused or replaced, and `workflows/entities.rb`.
- Modify: every `@db[:workflows]`, `@db[:workflow_requests]`, `@db[:approvals]` and `@db[:queued_messages]` caller in all files.

**Interfaces:**
- Produces:
  - `Dto::Phase < T::Enum` with exactly: `spec_writing spec_review spec_human_approval plan_writing plan_review plan_human_approval implementation implementation_review pr_ready done closed blocked paused cancelled`.
  - `Dto::Gate` (`spec`, `plan` or `implementation`) and `Dto::ControlAction` (`pause`, `resume`, `finish` or `cancel`).
  - `Dto::ArtifactSet`: `spec`, `plan` and `implementation`, each a `T.nilable(ArtifactRef)` with `commit` and `path: T.nilable(String)`. Serialized keys match today's JSONB.
  - `Dto::RoleConfig`: `cli`, `provider`, `model`, `family`, `launch_args: T::Array[String]`. `Dto::RoleAssignments`: `writer` and `reviewer`.
  - `Dto::WorkflowView`: every `workflows` column, typed.
  - `Workflows::Catalog` methods:
    - `#find(id:) -> T.nilable(Dto::WorkflowView)`
    - `#active_in_thread(channel_id:, thread_id:) -> T.nilable(Dto::WorkflowView)`
    - `#active -> T::Array[Dto::WorkflowView]`
  - `Workflows::Transitions` methods. Each runs under `Platform::Lock` keyed by the workflow id and an optimistic `version`:
    - `#control(workflow_id:, action:, expected_version:, paused_commit: T.nilable(String)) -> Result[Dto::WorkflowView]`. Error codes: `VersionChanged`, `Inactive`, `CannotPause`, `NotPaused`, `NotDelivered`, `AlreadyClosed`.
    - `#advance_approval(workflow_id:, gate:, expected_version:) -> Result[Dto::WorkflowView]`
    - `#archive(workflow_id:) -> void`
    - `#record_artifact(workflow_id:, gate:, ref:) -> Result[Dto::WorkflowView]`
    - `#enter(workflow_id:, phase:, expected_version:) -> Result[Dto::WorkflowView]`
  - `Workflows::Requests` methods:
    - `#create(inbox_id:, project_id:, digest:, parameters: Dto::RequestParameters, thread_id:) -> Result[Dto::RequestView]`, which is idempotent on `inbox_id` and digest
    - `#find(id:)`
    - `#mark(id:, state:, reason:)`
    - `#bind(id:, workflow: ...) -> Result[Dto::WorkflowView]`
  - `Workflows::Approvals#record(...) -> Result[Dto::ApprovalView]` and `#find(workflow_id:, gate:, commit:) -> T.nilable(Dto::ApprovalView)`.
  - `Workflows::Policy` keeps its methods, typed with `RoleConfig` and `VerifiedActor`.
  - The Services use cases (`Control`, `AdvanceApproval`, `DispatchPhasePrompt`, `RequestStart`, `Provision`, `ReconcileStart`, `ApproveCurrent`, `StartExisting`) keep today's ordering of checks and effects.
- [ ] **Step 1: Write the failing tests.**
  - `control with stale expected_version fails VersionChanged and writes nothing`
  - `resume restores saved_phase and clears paused_commit`
  - `artifact_set round-trips today's JSONB shape`
  - `malformed role_configurations row fails closed`
  - The existing commander and lifecycle examples keep their assertions.
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Verify.** Expected: baseline, with the workflow tables gone from the allowlist.
- [ ] **Step 5: Commit.** Message: `refactor: add workflows domain and workflow use cases`.

### Task 7: Sessions domain

**Files:**
- Create in `app/domains/sessions/`:
  - `entities/{runtime_session,session_operation,session_callback}.rb`
  - `dto/{session_role,session_state,operation_kind,operation_state,runtime_identity,session_view,operation_view,session_operation_job,renewal_job,error_code}.rb`
  - `{registry,operations,authenticate,callbacks,renewals}.rb`
- Move: `sessions/lifecycle.rb` to `app/services/sessions/*` per the file map. Move `Mattermost::WorkerChat` to `Services::Sessions::PostWorkerChat`, and `Reviews::Intake` session checks to `Sessions::Authenticate`.
- Delete: `Mattermost::WorkerChat::Workflow`, which is replaced by `Workflows::Dto::WorkflowView`.
- Modify: every `@db[:sessions]`, `@db[:session_operations]` and `@db[:callbacks]` caller. That includes `Routing`, `Coordinator`, `Commander` and `Requests`.

**Interfaces:**
- Produces:
  - `Sessions::Registry` methods:
    - `#find(id:)`
    - `#active(workflow_id:, role:) -> T::Array[Dto::SessionView]`
    - `#active_commander -> T.nilable(Dto::SessionView)`
    - `#pending_start(workflow_id: T.nilable(String), role:) -> T.nilable(Dto::SessionView)`
    - `#latest_generation(workflow_id: T.nilable(String), role:) -> Integer`
  - `Sessions::Operations` methods:
    - `#reserve(workflow_id: T.nilable(String), role:, configuration: Workflows::Dto::RoleConfig, credential_digest:) -> Result[Dto::OperationView]`. It creates the session and the start operation, then enqueues `SessionOperationJob`.
    - `#queue_stops(workflow_id:) -> void`
    - `#find(id:)`
    - `#mark(id:, state:, reason:)`
    - `#activate(session_id:, pane_id:, workspace_id:, identity:, state:) -> void`
    - `#deactivate(session_id:) -> void`
  - `Sessions::Authenticate#call(token:, generation:, roles: T::Array[Dto::SessionRole]) -> Result[Dto::SessionView]`. It checks digest, active state, expiry and the latest generation.
  - `Sessions::Callbacks#record(session_id:, generation:, key:, body_digest:) -> Result[String]`, with error code `KeyReused`.
  - `Sessions::Renewals#schedule(session:) -> String` and `#extend(session_id:, until:) -> void`.
  - Credential files go through `Adapters::Credentials::FileStore`, which is called from services only.
- [ ] **Step 1: Write the failing tests.**
  - `authenticate rejects stale generation`
  - `reserve is idempotent while a start is pending`
  - `runtime_identity round-trips and rejects missing fields`
  - `callback key reuse with changed body fails KeyReused`
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Verify.** Expected: baseline.
- [ ] **Step 5: Commit.** Message: `refactor: add sessions domain and session use cases`.

### Task 8: Reviews domain

**Files:**
- Create in `app/domains/reviews/`: `entities/review.rb`, `dto/{verdict,dispatch_state,review_view,review_prompt_job,review_release_job,review_callback_job,error_code}.rb`, `{rounds,verdicts}.rb`.
- Move: `reviews/coordinator.rb` and `reviews/intake.rb` to `app/services/reviews/*` per the file map. Move `Commander::Services#review_callback` there too.
- Modify: every `@db[:reviews]` caller.

**Interfaces:**
- Produces:
  - `Reviews::Rounds` methods:
    - `#open(workflow_id:, gate:, target_commit:, base_commit:, review_path:, reviewer: Workflows::Dto::RoleConfig) -> Result[Dto::ReviewView]`
    - `#latest(workflow_id:, gate:) -> T.nilable(Dto::ReviewView)`
    - `#latest_changes_requested(workflow_id:) -> T.nilable(Dto::ReviewView)`
    - `#mark_dispatch(id:, state:) -> void`
  - `Reviews::Verdicts#record(review_id:, review_commit:, verdict: Dto::Verdict) -> Result[Dto::ReviewView]`
- [ ] **Step 1: Write the failing tests.** `latest returns highest round` and `verdict on already-decided round fails`. Existing coordinator examples keep their assertions.
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Verify.** Expected: baseline.
- [ ] **Step 5: Commit.** Message: `refactor: add reviews domain and review use cases`.

### Task 9: Commander domain (Commander conversation)

**Files:**
- Create in `app/domains/commander/`:
  - `entities/{commander_request,followup,confirmation,conversation_binding}.rb`
  - `dto/{commander_request_state,commander_request_view,followup_status,followup_view,routing_evidence,binding_view,commander_dispatch_job,followup_job,error_code}.rb`
  - `{commander_requests,followups,bindings,confirmations}.rb`
- Move: `commander/{commander,followups,routing,approvals,requests,tools}.rb` to `app/services/commander/*` per the file map.
- Modify: every `@db[:commander_requests]`, `@db[:followups]`, `@db[:confirmations]` and `@db[:conversation_bindings]` caller.

**Interfaces:**
- Produces:
  - `Commander::CommanderRequests` methods:
    - `#create(inbox_id:, session_id:, credential_digest:, expires_at:) -> Result[Dto::CommanderRequestView]`, which is idempotent on `inbox_id`
    - `#authorize(id:, token_digest:, states:) -> Result[Dto::CommanderRequestView]`
    - `#mark(id:, state:, reason:)`
    - `#first_for_session(session_id:) -> T.nilable(Dto::CommanderRequestView)`
  - `Commander::Followups` methods: `#create(inbox_id:, workflow_id:, session: T.nilable(Sessions::Dto::SessionView), evidence: Dto::RoutingEvidence) -> Result[Dto::FollowupView]`, `#find`, `#for_inbox`, `#mark`.
  - `Commander::Bindings` methods: `#bind(channel_id:, thread_ids: T::Array[String], user_id:, workflow_id:, inbox_id:, at:) -> void` and `#find(channel_id:, thread_id:, user_id:) -> T.nilable(Dto::BindingView)`.
  - `Services::Commander::Tools#call(name: Dto::ToolName, arguments: Dto::ToolArguments, token:) -> Result[Dto::ToolResponse]`. The tool results are typed DTO lists that serialize to today's JSON. `Adapters::Mcp` and `Adapters::Http::Commander` serialize them.
- [ ] **Step 1: Write the failing tests.**
  - `followup creation is idempotent per inbox`
  - `routing_evidence round-trips`
  - `tools reject unexpected fields as a failure result`
  - The existing `commander_tools_spec` and `commander_spec` keep their assertions.
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Verify.** Expected: baseline.
- [ ] **Step 5: Commit.** Message: `refactor: add commander domain and commander use cases`.

### Task 10: Composition root and completion

**Files:**
- Create: `app/services/{configuration,composition,job_handlers}.rb`
- Delete: `app/domains/commander/services.rb`
- Modify: `bin/*`, `config/routes.rb`, `integration-backend/AGENTS.md`, `integration-backend/README.md` (layout section), `docs/superpowers/plans/2026-09-30-digitaltwin-phase-0.md` (paths), `.agents/changelog.md`
- Empty: `spec/contracts/architecture_allowlist.yml`

**Interfaces:**
- Produces:
  - `Services::Configuration.from_env -> Services::Configuration`, a `T::Struct` holding every ENV value read today, with the same names and defaults.
  - `Services::Composition.new(configuration:)`, which exposes each use case.
  - `Services::JobHandlers#call -> T::Hash[Platform::Jobs::Dto::JobKind, Platform::Jobs::Handler]`. Its kind mapping equals today's `handlers` map, including `commander.dispatch` only when the commander role is configured.
- [ ] **Step 1: Write the failing tests.**
  - `job_handlers maps exactly today's kinds`
  - The architecture spec with an empty allowlist
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement.** Replace remaining `ENV.fetch` calls under `app/` with `Configuration`, except in `configuration.rb`.
- [ ] **Step 4: Verify.**
  - Commands: `bundle exec spoom srb tc`, `bundle exec rubocop`, `bundle exec rspec`, and `grep -rnE "db\[:|raw_db_connection|returns\(Object\)|T::Hash\[(Symbol|String), Object\]" app`.
  - Expected: no type errors, no new RuboCop offenses, the baseline failures, and an empty grep.
- [ ] **Step 5: Commit.** Message: `refactor: add composition root and finish layered layout`.

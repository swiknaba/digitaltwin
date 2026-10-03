# Commander first release: implementation plan

**Status:** Draft for review. No implementation or live provider run is authorized by writing this plan.

**Behavior contract:** [Approved Commander feature spec](../../commander-feature-spec.md), approved choices at `fed73ad354d4cacbfa360035cf5ea432ddc2dbaa`. The first enabled version covers conversation, status, and routing for existing projects. Commander chooses the thread from verified context; memory includes project decisions, working preferences, and lessons learned. Enrollment and emergency tools follow later.

**Baseline:** Application main `552557c991e0ff8081ca0041e56eb83802fd37a2`. [Post-merge CI](https://github.com/swiknaba/digitaltwin/actions/runs/37148774025) passed 25 root checks, 253 backend examples, RuboCop and whole-project Sorbet. Chat, Herdr, MCP and callbacks were real; the agent was scripted. Selected-provider operation and production activation remain unverified.

## What we will reuse and what is missing

| Area | Existing code | Work in this plan |
| --- | --- | --- |
| Conversation | `services/inbound/`, `services/master/ingest_prompt.rb`, `dispatch.rb`, `reply.rb`; durable inbox/outbox | Real configured Commander, useful grounded replies, bounded identical callback retry where required |
| Routing | `services/master/route_followup.rb`, `deliver_followup.rb`; bindings, evidence and queues | Wider reliable context retrieval, verified thread selection for new work, explicit ambiguity and reuse checks |
| Status and notices | Workflow/session/job DTOs, `last_verified_at`, durable outbox | Human-readable status with staleness, source links and deduplicated Commander milestones |
| Memory | Git adapters and the agreed Git memory model | Request-bound read/remember/correct operations, provenance and restart-safe writes |
| Controls and recovery | Version-bound workflow controls and exact human reconciliation | Expose truthful results; safe release of previously blocked, never-sent jobs |
| Enablement | `domains/workflows/policy.rb` returns false; default worker has no application handlers | Bounded acceptance entrypoint, capability-specific authorization, private operator overlay and reviewed activation |

Keep `controller`, `master`, existing routes and persistence identifiers. Follow `integration-backend/AGENTS.md` and the DDD refactor contract. Ruby changes use strict Sorbet, explicit DTO/results, one class per file and Kirei persistence. No dependency upgrades, new signing keys, Hermes integration, provider login automation, mobile work or production deployment.

## Execution order and ownership

The backend owner implements application changes; the integrator owns Compose, scripts, root tests and shared contracts. Runtime changes stay with its owner. Use isolated branches and merge reviewed dependencies. Each task starts with failing behavior tests, adds the smallest implementation, runs its focused checks and the complete backend `bin/check`, and records interfaces and evidence. Reserve migration numbers with the backend owner; current migrations end at 008. Do not renumber old migrations.

### 1. Define the first-release contracts and acceptance cases

**Files:** Shared `docs/interfaces/` contracts; existing MCP DTOs under `services/master/dto/`; `spec/domains/commander_spec.rb` and adapter specs.

- [ ] Map every approved behavior to an automated case and, where necessary, a live acceptance case. Mark later features separately rather than claiming full Phase 0 acceptance.
- [ ] Define typed status, thread candidate, memory record and dispatch grant contracts before adding tools. Preserve existing tool schemas; add/version interfaces explicitly and update their HTTP serializer and packaged clients together.
- [ ] Define the live acceptance profile: exact application/client/Runtime revisions, selected CLI/provider/model, chat identities, allowed projects, permitted operations and an expiry. It contains references and sanitized identifiers, never credentials.
- [ ] Pin negative cases: bots cannot authorize work, wrong/expired capabilities fail, inaccessible context is excluded, changed/ambiguous targets cause no effect, and no tool starts an unrelated session.

**Exit:** Reviewed contracts and acceptance matrix; production policy still closed.

### 2. Prepare real operator configuration and a bounded acceptance path

**Files:** `services/configuration.rb`, `services/composition.rb`, `bin/worker`; proposed `scripts/test-commander-live` and private overlay documentation. Extend root tests without replacing `scripts/test-full-stack`.

- [ ] Document token-file mounts and IDs for the existing Mattermost human, listener and bots; Commander/project channels and memberships; trusted role file; callback URL; provider login and selected CLI MCP settings. Enable the opt-in listener and worker handlers only with complete validated configuration. Default credential-free boot stays unchanged.
- [ ] Add a separate live acceptance entrypoint using real application handlers. Bind it to an explicitly selected disposable project/database, allowlisted destinations, operation budget and deadline. It must not replace the normal worker or import the scripted Pi agent as provider proof.
- [ ] Use existing operator credentials through restricted mounts; create no signing keys or persistent provider tokens. Never copy login state into Git, images, logs, caches or artifacts. A real run requires explicit authorization for provider usage and its budget.
- [ ] Introduce the capability-check plumbing needed for acceptance at the effect boundaries before any real run. The acceptance composition grants only the selected test capability/profile and registers only its needed handlers; normal dispatch remains closed. Test rejection of a mismatched project, profile, operation or expiry. Task 7 adds production activation validation; no unrestricted environment switch is introduced.

**Exit:** Reproducible bounded live-test path and sanitized configuration checks. No provider run merely because configuration exists.

### 3. Finish conversation, status and milestone delivery

**Files:** `services/master/`, existing workflow/session public queries, `services/outbound/`, `adapters/http/tool_json.rb`, MCP manifest DTOs.

- [ ] Add a typed request-bound status read: accessible project/task, phase, current role, waiting reason, approval version, pending instructions, last verified Runtime time and source/artifact links. Mark Runtime status stale after 60 seconds without verification; unknown is never success.
- [ ] Give the selected Commander clear role instructions: answer operational questions without a coding review cycle, use authoritative tools, delegate coding, distinguish received/queued/delivered, and send replies to the source conversation.
- [ ] Add outbox summaries for approval-needed, blocked and result-ready events. Deduplicate by event and destination; detailed worker progress stays in the project thread. Record queued-versus-delivered status from actual receipts.
- [ ] Test two source channels/threads, revoked membership, repeated callbacks, concurrent requests, restart and uncertain outbox delivery. Retain the original request capability when replaying the identical reply; use bounded retries, never changed payloads.

**Exit:** Status is grounded and honest; one event produces one summary, with correct source links and no crossed replies.

### 4. Select threads from context without creating duplicate work

**Files:** `services/master/route_followup.rb`, `tools.rb`, `domains/commander/bindings.rb`; `services/workflows/request_start.rb`, `provision.rb`; new typed selection DTOs and specs.

- [ ] Extend context retrieval beyond the current ten recent global inbox entries so one busy project cannot hide another relevant task. Use bounded, project/thread-aware queries, source verification and current membership checks.
- [ ] Preserve target precedence: verified task thread, explicit human selection, grounded interpretation, then recent same-human binding. If evidence conflicts or several targets remain plausible, return a concise clarification without queuing an effect. Do not force manual selection when one verified target is clear.
- [ ] For new work in an enrolled project, let Commander propose an existing unused root with cited context. Add server-side verification of root identity, destination membership, project mapping and absence of an active workflow. Current `start_workflow` has no thread input and `RequestStart` only accepts the original source thread: bridge that gap with an explicit typed operation, not a fabricated source message or unchecked model ID.
- [ ] Never use an active task thread for unrelated work. If there is no suitable verified root, ask a short clarification/request for a new root. Automatic root creation is not required for this first release; existing creation/reconciliation code must not silently substitute another destination.
- [ ] Verify parallel tasks in one repository retain different worktrees/branches and correct Writer identities. Follow-ups, review waits and renewal reuse the same task/session. Test two plausible targets, expired bindings, source edits/deletion and missing conversations.

**Exit:** Clear context routes automatically; ambiguity causes no action; new work and follow-ups cannot overwrite or duplicate another task.

### 5. Add durable decisions, preferences and lessons

**Files:** Proposed `domains/memory/` DTOs/public services, `services/master/` memory orchestration, narrow `adapters/git/` memory adapter, MCP DTOs; coordinated migration only if durable operation receipts need a new table.

- [ ] Support request-bound read, remember and correct operations for the configured memory repository and project `.agents/memory.md`. Record scope, provenance, author/source, version and superseded facts. Do not hardcode a repository slug.
- [ ] Recall project decisions, working preferences and lessons through Commander context. Recheck access before returning project material. Memory helps interpretation; it never supplies missing authorization or overrides verified task state.
- [ ] Let a human ask what is remembered and correct it. Save only facts grounded in the request or verified work; clarify inferred or conflicting preferences. Keep secrets, login state and transient scheduler state out of memory.
- [ ] Follow the existing memory policy: small additive updates may commit to the configured memory default branch; substantial reorganization uses a branch/PR. Do not expose a general shell/Git tool or automatically merge/publish. Project memory changes respect the task worktree and review lock.
- [ ] Journal memory writes by source request and expected revision. Replay returns the recorded result; a crash or uncertain Git outcome is reconciled against the exact commit before any repeat. Test path confinement, concurrent edits, duplicate requests, correction, restart and real local Git commits.

**Exit:** Facts survive a fresh Commander conversation, corrections are visible, and retries do not create duplicate commits. No Hermes dependency or scheduled memory grooming.

### 6. Preserve controls, review exclusion and recovery

**Files:** Existing `services/workflows/control.rb`, `services/master/record_approval.rb`, `deliver_followup.rb`, recovery services and `platform/jobs/store.rb`.

- [ ] Exercise pause/current-step completion, saved-result resume, cancellation/stop confirmation and exact-version approvals through Commander tools. Surface a changed version or blocked operation plainly instead of reporting success.
- [ ] Hold Writer instructions through review/pause, then revalidate the same workflow, source, session/generation and revision before releasing them. No competing Writer, automatic replacement conversation or bypass of review gates.
- [ ] Add a typed operator preview/apply procedure for evidence-blocked jobs: select explicit IDs, prove the block is the acceptance gate, verify no effect began or live lease exists, and recheck source membership, workflow/version and Runtime identity under the relevant lock. Only then use `Store#requeue_blocked`. Preserve a durable audit and return per-job outcomes.
- [ ] Do not bulk-reset failed/uncertain jobs. Existing `recover-*` commands remain exact-human reconciliation, not permission to replay an action. Restart restores healthy verified conversations; missing/replaced identities stay blocked.
- [ ] `finish` succeeds only with verified delivery state and positive stop receipts. Broader PR-delivery implementation remains separate Phase 0 work; report unavailable/unverified finish honestly rather than manufacturing a done state.

**Exit:** User controls and re-arming are bounded, auditable and safe across concurrency and restart.

### 7. Capture live evidence, then enable only validated capabilities

**Files:** Proposed typed activation domain/services and profile adapter; `domains/workflows/policy.rb`, `services/composition.rb`, every effect call site; sanitized `tests/evidence/` and shared acceptance docs.

- [ ] Complete the capability-check plumbing introduced in Task 2 and remove the legacy all-or-nothing dispatch boolean from effect authorization. Commander start/prompt/renewal, Writer follow-up, workflow provisioning/phase prompts, Reviewer dispatch and memory writes require their own validated profile. Keep the existing business/review policies intact.
- [ ] Read activation from an operator-owned local record referencing a reviewed release-bound acceptance manifest. Bind application/client/Runtime identities, selected role configuration, chat/project mappings and expiry. Missing, expired, changed or mismatched evidence fails closed. Bind executable source/build identities so an evidence-only documentation commit does not create a circular release dependency. No model-written activation and no plain `DISPATCH=true` bypass.
- [ ] First capture an authorized real Commander run: authenticated human post, actual Herdr conversation identity, real selected-provider prompt and settled state, MCP initialize/list/status/context call, callback in the original thread, identical replay and restart with the same verified conversation. Record sanitized commands, versions, correlations and results.
- [ ] Before enabling Writer follow-ups or new workflow lifecycle, also validate the configured Writer/Reviewer lifecycle and settled/review handshake, provider diversity, two isolated worktrees, review queue/release and concurrent follow-ups. Commander acceptance alone cannot unlock these capabilities. Unvalidated providers/actions stay blocked.
- [ ] Review the evidence and activation code independently, then explicitly activate only the reviewed release/profile. Preview/revalidate/re-arm selected unsent jobs; rerun the real human scenario. Disablement stops new effects and preserves receipts/current state for reconciliation.

**Exit:** A configured human can converse and route work through a real Commander within validated capabilities. Basic conversation can roll out first; the approved first-version routing/memory acceptance remains open until its dependent checks pass.

### 8. Integrate, test and hand off

- [ ] Run full backend `bin/check` with two disposable test databases; keep focused architecture/contract checks supplemental. Run `scripts/test-full-stack` and hosted CI on the exact candidate head. New schema changes must migrate from an empty database and roll back through real Rake tasks.
- [ ] Extend deterministic integration coverage for status, routing, review queues, isolated worktrees, memory and activation/re-arming negative cases. Provider-free CI never claims live LLM acceptance; keep the live runner opt-in and outside ordinary PR execution.
- [ ] Add the operator overlay example/runbook, sanitized evidence and a behavior-to-check matrix. Update historical plan/setup statuses without rewriting immutable historical results. Record what is implemented, simulated, live-tested, blocked and deferred.
- [ ] Review and merge in dependency order. Any runtime client change updates the exact source revision, checksums, named context and provenance tests together. No credentials or images are published as part of these code checks.

## First-version acceptance for human review

- [ ] A real human asks Commander a question and receives a grounded reply in the right conversation.
- [ ] Status shows actual tasks, roles, waits and results; unknown/stale state is explicit.
- [ ] A clear follow-up selects the existing thread/session automatically; ambiguity asks one short question and causes no effect.
- [ ] New work in an existing project selects a verified unused thread and keeps its own worktree; two same-repository tasks never cross replies or files.
- [ ] Review/pause retain instructions; resume revalidates; cancellation reports confirmed stops; approvals remain version-bound.
- [ ] Decisions, preferences and lessons survive restart and can be inspected/corrected without duplicate writes.
- [ ] Wrong/expired capabilities, revoked membership, changed releases and unvalidated role profiles fail closed. An uncertain effect is never automatically repeated.
- [ ] Important milestones reach Commander once with task links; project threads retain the detail.

Enrollment, general Git/deployment/emergency operations, automatic merge, mobile/push, production infrastructure and complete Phase 0 delivery remain later work. This plan does not authorize their implementation or live usage.

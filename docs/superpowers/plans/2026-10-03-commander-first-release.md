# Commander First Release Implementation Plan

> **For agentic workers:** Use `superpowers:subagent-driven-development` or `superpowers:executing-plans` to implement the approved tasks. Track progress with checkboxes.

**Goal:** Let us talk to Commander, delegate work to our fleet, and steer existing projects without losing context.

**Architecture:** Extend the existing Kirei backend and Herdr sessions. Keep authorization, workflow state, and delivery checks in the backend. Commander interprets requests through its selected CLI and private MCP tools.

**Tech stack:** Ruby 4.0, locked Kirei, Sorbet, PostgreSQL, Mattermost, Herdr, and the existing Runtime clients.

**Spec:** [Approved Commander behavior](../../commander-feature-spec.md). This plan is a draft for review; it does not authorize feature implementation or provider calls.

## Global Constraints

The first release covers conversation, status, contextual routing, memory, and controls for existing projects.
Project enrollment, emergency tools, deployment tools, voice, and mobile acceptance come later.

- Use **Commander** and **Commander Shepard** consistently. Keep the default handle `@agent`.
- Require a specific second confirmation for destructive or irreversible operations.
- Keep human approval for reviewed specifications and plans. Bind each approval to the task and exact commit.
- Keep separate branches and worktrees for parallel tasks. Writer and Reviewer share one task worktree and take turns.
- Only Commander starts independent fleet sessions. Workers need approval for additional independent sessions; harness subagents remain permitted.
- Preserve sender authority, project membership, reply destinations, and separate fleets.
- Do not merge, deploy, create credentials, or make paid provider calls through plan approval alone.
- Keep dispatch disabled until the relevant real CLI checks pass and activation receives approval.

## Starting point

The automated stack already verifies real chat, queues, Herdr transport, callbacks, and restart behavior with a scripted agent.
It does not verify a real provider conversation. Production dispatch remains disabled.
The earlier naming change updated the domain and display name, while retaining implementation identifiers.
[The naming audit](../../interfaces/commander-naming-upgrade.md) lists those leftovers.

Complete these tasks in order. Each task ends with a tested commit and review before the next task begins.
Use failing behavior tests, implement the smallest change, then run the checks below.

## Task 1: Give the system one name

**Goal:** Canonical application roles, services, commands, and documentation all identify the coordinator as Commander.

**Work:**

- [ ] Rename the remaining application namespaces, configuration keys, private routes, and commands listed in the naming audit.
- [ ] Add migration `009_commander_names` for stored roles, requests, job kinds, workflow configuration, and conversation bindings.
- [ ] Preserve session identities, request digests, deduplication keys, existing results, and historical evidence.
- [ ] Update the Runtime client checksums and document the coordinated upgrade and rollback.

**Done:** A populated version 8 database upgrades and rolls back without losing work or repeating effects.
Old clients reach the same authenticated handlers during the transition. New instructions and interfaces use Commander.

## Task 2: Talk to a real Commander

**Goal:** A human can mention Commander and receive its actual CLI response in the same conversation.

**Work:**

- [ ] Configure the selected Commander profile through private operator files.
- [ ] Use the specified Gemini default, or an operator-selected CLI whose Herdr and MCP behavior passes validation.
- [ ] Separate conversation permission from permission to start worker workflows.
- [ ] Verify one bounded real CLI conversation, including MCP calls, completion, and a repeated callback.
- [ ] Record the selected versions and sanitized evidence; request approval before enabling conversation dispatch.

**Done:** The real Commander replies once to the correct source thread.
An unauthorized sender, stale request credential, or mismatched session cannot prompt it.
Missing credentials leave this task explicitly blocked; scripted-agent results cannot complete it.

## Task 3: Ask what the fleet is doing

**Goal:** “What is happening?” returns useful status, blockers, approvals, and links across projects we can access.

**Work:**

- [ ] Add a status operation using stored workflows, sessions, reviews, approvals, and delivery receipts.
- [ ] Report the last verified state when the Runtime cannot provide current status.
- [ ] Send milestones, approval requests, blockers, and result links to Commander chat once.

**Done:** Two projects show distinct tasks, their current waits, and their source threads.
An inaccessible project stays hidden. Unverified delivery is never described as delivered.
Routine task messages remain in project threads.

## Task 4: Delegate work to the right thread

**Goal:** Commander selects the project and thread from context and delegates work without mixing unrelated tasks.

**Work:**

- [ ] Extend context reads to the relevant project and task conversation beyond the current ten-message window.
- [ ] Extend `start_workflow` with a proposed thread and cited context.
- [ ] Verify the project, membership, root post, and available thread before binding new work.
- [ ] Reuse the active task for follow-ups. Give unrelated work a separate workflow, branch, and worktree.
- [ ] Verify real Writer and Reviewer CLI handoffs before enabling the corresponding workflow operations.
- [ ] Keep coding’s reviewed specification, human approval, reviewed plan, human approval, implementation, review, and pull-request sequence.

**Done:** “Also add search” reaches the existing task without asking us to choose its thread.
Ambiguous context triggers one clarification and no action.
New work uses an appropriate unoccupied project thread; an occupied thread cannot acquire a competing workflow.
Two tasks in one repository remain separate. Opening a pull request does not merge or deploy it.

## Task 5: Remember decisions and working preferences

**Goal:** Later conversations retain project decisions, our working preferences, and lessons learned.

**Work:**

- [ ] Add bounded operations to read, remember, and correct entries.
- [ ] Use the configured shared memory repository and each project’s `.agents/memory.md`.
- [ ] Record the source request and revision; serialize conflicting writes and reconcile uncertain Git outcomes.

**Done:** A remembered preference survives a fresh conversation and backend restart.
A correction updates the intended entry. Duplicate requests create no duplicate memory.
Memory updates follow human requests or agent instructions; no scheduled grooming or Hermes integration is added.

## Task 6: Steer work while it runs

**Goal:** We can answer questions, add instructions, pause, resume, cancel, and finish the intended task.

**Work:**

- [ ] Route answers and controls from either Commander chat or the task thread.
- [ ] Let the current step finish after pause, then prevent the next step.
- [ ] Queue Writer instructions during review; release them only when the reviewed version may change.
- [ ] Recheck approvals and revisions on resume. Close delivered work only on an explicit finish request.

**Done:** A review keeps its exact revision while new instructions wait, without starting another Writer.
Pause and resume preserve results. Cancel reports verified stops without erasing work.
Finish rejects unfinished work. Silence never closes a task.

## Task 7: Continue safely after a restart

**Goal:** Commander resumes verified work and clearly identifies work that needs reconciliation.

**Work:**

- [ ] Restore task state and reuse matching, healthy conversations.
- [ ] Revalidate queued work against its human source, session identity, permissions, and current revision.
- [ ] Provide bounded recovery for blocked work whose external action never began.
- [ ] Keep uncertain actions blocked until remote evidence or human reconciliation resolves them.

**Done:** Restarting during a prompt, review, or reply creates no duplicate work or replacement session.
A lost receipt remains uncertain. A revoked sender cannot release queued work.
Resolved work continues in its original conversation.

## Task 8: Release the first usable Commander

**Goal:** The approved first-release behavior works together, with an operating guide that matches the tested system.

**Work:**

- [ ] Run the complete automated suite and record CI against the final commit.
- [ ] Run the approved real CLI acceptance scenarios for conversation, delegation, review, memory, controls, and restart.
- [ ] Update setup, recovery, activation, and disable instructions with the accepted profiles and remaining limits.
- [ ] Review the final changes and evidence before requesting release activation.

**Done:** A human can request work, clarify it, follow progress, approve exact artifacts, and receive a reviewed result link.
The evidence identifies real provider checks separately from scripted fixtures.
Unverified operations remain disabled; disabling dispatch preserves existing results and conversations.

## Implementation map

Paths below identify the existing code boundaries. Task 1 renames `services/master/` to `services/commander/` before later tasks use it.
Keep new Ruby values in separate, strictly typed files and retain the repository’s domain/service/adapter boundaries.

| Task | Main changes | Behavior tests |
| --- | --- | --- |
| 1 | Session and speaker enums, Commander request entity, routes, configuration, commands, migration 009, Runtime client manifest | Add `spec/integration/commander_naming_migration_spec.rb`; extend HTTP, parser, digest, and installed-client tests |
| 2 | `services/commander/{ingest_prompt,dispatch,reply}.rb`, `services/sessions/`, `domains/workflows/policy.rb`, `services/job_handlers.rb` | Extend `spec/domains/commander_spec.rb`; add a separately approved real-CLI acceptance runner |
| 3 | Add `services/commander/workflow_status.rb` and typed status DTOs; extend `tools.rb`, HTTP serialization, and milestone delivery | Add status specs; extend Commander tool and outbox specs |
| 4 | `services/commander/{tools,route_followup}.rb`, messaging context reads, `services/workflows/{request_start,provision}.rb` | Extend routing, workflow, and lifecycle specs with cross-project, ambiguous, and occupied-thread cases |
| 5 | Add a memory domain, typed entry DTOs, `services/commander/` memory operations, and a bounded Git memory adapter | Add memory domain/service specs and concurrent-write/restart integration cases |
| 6 | `services/workflows/control.rb`, `services/reviews/release_queued.rb`, Commander tools | Extend lifecycle/review specs with queued answers, pause boundaries, cancellation, and premature finish |
| 7 | Commander/session recovery services and `platform/jobs/store.rb` | Extend lifecycle/job specs with lost receipts, revoked sources, and matching-session recovery |
| 8 | `tests/`, `scripts/`, current interface docs, operator evidence | Run automated and separately authorized real CLI acceptance against the release commit |

### New operation contracts

- Status reads return typed task summaries: project, workflow, thread, phase, wait reason, verified session state, artifact links, and delivery state.
- `start_workflow` accepts `project_id`, `title`, proposed `thread_id`, and cited inbox IDs. The backend returns a verified request receipt.
- Memory operations identify shared or project scope and return an entry ID, content, source, and revision.
- Controls retain `workflow_id`, action, and expected version. The backend derives actor authority from the verified human source.

### Checks for every implementation task

Run `integration-backend/bin/check` with both disposable test databases. Expect passing RSpec, RuboCop, and whole-project Sorbet checks.
Run `scripts/test-full-stack` for cross-service changes. Expect all root checks to pass; opt-in tests must execute, not skip.
Neither command proves real provider behavior because the full-stack agent is scripted.

### Review Focus

1. Two plausible tasks: clarify before routing; test in Task 4.
2. Access revoked after queueing: reject before delivery or recovery; test in Tasks 2 and 7.
3. New instructions during review: preserve the reviewed revision and queue order; test in Task 6.
4. A result may already exist after a lost receipt: reconcile without replay; test in Tasks 5 and 7.
5. Old stored names during upgrade: preserve conversations, digests, and deduplication; test in Task 1.

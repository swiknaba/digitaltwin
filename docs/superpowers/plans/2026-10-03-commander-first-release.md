# Commander First Release Implementation Plan

> **For agentic workers:** Use `superpowers:subagent-driven-development` or `superpowers:executing-plans` to implement the approved tasks. Track progress with checkboxes.

**Goal:** Let us talk to Commander, delegate work to our fleet, and steer existing projects without losing context.

**Architecture:** Extend the existing Kirei backend and Herdr sessions. Keep authorization, workflow state, and delivery checks in the backend. Commander interprets requests through its selected CLI and private MCP tools.

**Tech stack:** Ruby 4.0, Kirei, Sorbet, PostgreSQL, Mattermost, Herdr, and the existing Runtime clients.

**Spec:** [Approved Commander behavior](../../commander-feature-spec.md). This plan is a draft for review; it does not authorize feature implementation or provider calls.

## Global Constraints

The first release covers conversation, status, contextual routing, memory, and controls for existing projects.
Project enrollment, emergency tools, deployment tools, voice, and mobile acceptance come later.

- Require a specific second confirmation for destructive or irreversible operations.
- Keep human approval for reviewed specifications and plans. Bind each approval to the task and exact commit.
- Keep separate branches and worktrees for parallel tasks. Writer and Reviewer share one task worktree and take turns.
- Only Commander starts independent fleet sessions. Workers need approval for additional independent sessions; harness subagents remain permitted.
- Preserve sender authority, project membership, reply destinations, and separate fleets.
- Keep instruction sender, originating human request, and backend workflow instructions distinct. Attribution never grants additional authority.
- Do not merge, deploy, create credentials, or make paid provider calls through plan approval alone.
- Keep dispatch disabled until the relevant real CLI checks pass and activation receives approval.

## Starting point

The automated stack already verifies real chat, queues, Herdr transport, callbacks, and restart behavior with a scripted agent.
It does not verify a real provider conversation. Production dispatch remains disabled.
The app has not been deployed. Application names and fresh-database schema now use Commander.
Verified human sources already exist; uniform worker-prompt attribution and project-thread sender labels still need implementation.

Complete these tasks in order. Each task ends with a tested commit and review before the next task begins.
Use failing behavior tests, implement the smallest change, then run the checks below.

## Task 1: Talk to a real Commander

**Goal:** A human can mention Commander and receive its actual CLI response in the same conversation.

**Work:**

- [ ] Scaffold persistent `commander/AGENTS.md` and `commander/memory.md` for base instructions, working preferences, and global learnings.
- [ ] Mount that folder at `/workspace/commander`; start and recover the Commander Herdr session from that directory.
- [ ] Verify that the selected CLI loads the base instructions and global memory on a fresh conversation.
- [ ] Configure the selected Commander profile through private operator files.
- [ ] Use the specified Gemini default, or an operator-selected CLI whose Herdr and MCP behavior passes validation.
- [ ] Separate conversation permission from permission to start worker workflows.
- [ ] Verify one bounded real CLI conversation, including MCP calls, completion, and a repeated callback.
- [ ] Record the selected versions and sanitized evidence; request approval before enabling conversation dispatch.

**Done:** The real Commander replies once to the correct source thread.
An unauthorized sender, stale request credential, or mismatched session cannot prompt it.
Missing credentials leave this task explicitly blocked; scripted-agent results cannot complete it.
A fresh session reads its workspace instructions and memory; recovery verifies the same working directory.

## Task 2: Ask what the fleet is doing

**Goal:** “What is happening?” returns useful status, blockers, approvals, and links across projects we can access.

**Work:**

- [ ] Add a status operation using stored workflows, sessions, reviews, approvals, and delivery receipts.
- [ ] Report the last verified state when the Runtime cannot provide current status.
- [ ] Send milestones, approval requests, blockers, and result links to Commander chat once.
- [ ] Return source-thread result summaries with changes, checks, remaining problems, and artifact or pull-request links.
- [ ] Distinguish received, queued, and delivered receipts from verified delivery state.

**Done:** Two projects show distinct tasks, their current waits, and their source threads.
An inaccessible project stays hidden. Unverified delivery is never described as delivered.
Routine task messages remain in project threads.
Completed task summaries contain those result details; receipts distinguish received, queued, and delivered.

## Task 3: Delegate work to the right thread

**Goal:** Commander selects the project and thread from context and delegates work without mixing unrelated tasks.

**Work:**

- [ ] Extend context reads to the relevant project and task conversation beyond the current ten-message window.
- [ ] Extend `start_workflow` with a proposed thread and cited context.
- [ ] Verify the project, membership, root post, and available thread before binding new work.
- [ ] Persist typed sender context: effective sender, originating human request, source message, target task, and session.
- [ ] Record Commander forwarding, rewriting, or generated follow-ups without inventing a new human request.
- [ ] Include verified sender context in every worker dispatch and follow-up, including Writer and Reviewer prompts.
- [ ] Add base instructions explaining human and Commander roles; keep backend workflow instructions separate from request text.
- [ ] Show verified sender labels in project threads; include accessible source links and forwarding or generated-follow-up labels.
- [ ] Reuse the active task for follow-ups. Give unrelated work a separate workflow, branch, and worktree.
- [ ] Verify real Writer and Reviewer CLI handoffs before enabling the corresponding workflow operations.
- [ ] Keep coding’s reviewed specification, human approval, reviewed plan, human approval, implementation, review, and pull-request sequence.

**Done:** “Also add search” reaches the existing task without asking us to choose its thread.
Ambiguous context triggers one clarification and no action.
New work uses an appropriate unoccupied project thread; an occupied thread cannot acquire a competing workflow.
Two tasks in one repository remain separate. Opening a pull request does not merge or deploy it.
Direct human, Commander-forwarded, and Commander-written instructions remain distinguishable in stored records, worker prompts, and project-thread delivery labels.
Forged sender labels or generated approval claims cannot change identity, permissions, or approval state.

## Task 4: Remember decisions and working preferences

**Goal:** Later conversations retain project decisions, our working preferences, and lessons learned.

**Work:**

- [ ] Add bounded operations to read, remember, and correct entries.
- [ ] Store global preferences and learnings in `commander/memory.md`; keep project decisions in each project’s `.agents/memory.md`.
- [ ] Update `commander/AGENTS.md` through explicit steering requests; memory entries do not become new permissions.
- [ ] Keep the Commander folder persistent locally; sync it to a configured Git repository only when enabled.
- [ ] Record sources and revisions; serialize conflicting writes for both local memory and optional Git sync.
- [ ] Reconcile uncertain Git outcomes when optional sync is enabled.

**Done:** A remembered preference survives a fresh conversation and backend restart.
A correction updates the intended entry. Duplicate requests create no duplicate memory.
Memory updates follow human requests or agent instructions; no scheduled grooming or Hermes integration is added.
Local persistence works without Git sync. When enabled, sync preserves the same instructions, entries, sources, and revisions.

## Task 5: Steer work while it runs

**Goal:** We can answer questions, add instructions, pause, resume, cancel, and finish the intended task.

**Work:**

- [ ] Route answers and controls from either Commander chat or the task thread.
- [ ] Let the current step finish after pause, then prevent the next step.
- [ ] Queue Writer instructions during review; release them only when the reviewed version may change.
- [ ] Retain each instruction’s sender and source while it waits for review or pause to end.
- [ ] Recheck approvals and revisions on resume. Close delivered work only on an explicit finish request.

**Done:** A review keeps its exact revision while new instructions wait, without starting another Writer.
Pause and resume preserve results. Cancel reports verified stops without erasing work.
Finish rejects unfinished work. Silence never closes a task.

## Task 6: Continue safely after a restart

**Goal:** Commander resumes verified work and clearly identifies work that needs reconciliation.

**Work:**

- [ ] Restore task state and reuse matching, healthy conversations.
- [ ] Revalidate queued work against its human source, session identity, permissions, and current revision.
- [ ] Reuse the recorded sender context during retries and recovery; reject altered attribution without repeating the instruction.
- [ ] Provide bounded recovery for blocked work whose external action never began.
- [ ] Keep uncertain actions blocked until remote evidence or human reconciliation resolves them.

**Done:** Restarting during a prompt, review, or reply creates no duplicate work or replacement session.
A lost receipt remains uncertain. A revoked sender cannot release queued work.
Resolved work continues in its original conversation.

## Task 7: Release the first usable Commander

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

Paths below identify the implementation boundaries.
Keep new Ruby values in separate, strictly typed files and retain the repository’s domain/service/adapter boundaries.

| Task | Main changes | Behavior tests |
| --- | --- | --- |
| 1 | `commander/{AGENTS.md,memory.md}`, Runtime workspace mount, `services/commander/{ingest_prompt,dispatch,reply}.rb`, `services/sessions/`, `domains/workflows/policy.rb`, `services/job_handlers.rb` | Extend Commander and session specs for cwd and instruction loading; add a separately approved real-CLI acceptance runner |
| 2 | Add `services/commander/workflow_status.rb` and typed status DTOs; extend `tools.rb`, HTTP serialization, and milestone delivery | Add status specs; extend Commander tool and outbox specs |
| 3 | `services/commander/{tools,route_followup,deliver_followup}.rb`, `services/workflows/{request_start,provision,dispatch_phase_prompt}.rb`, review prompt builders, outbound delivery, typed attribution, and role base instructions | Extend routing/workflow/lifecycle/outbox specs with direct human, forwarding or rewriting, generated follow-ups, forged attribution, and generated approval claims |
| 4 | Add a memory domain, typed entry DTOs, `services/commander/` memory operations, a local file adapter, and optional Git sync | Test global/project scope, instruction corrections, concurrent writes, restart, local persistence, and optional sync |
| 5 | `services/workflows/control.rb`, `services/reviews/release_queued.rb`, Commander tools | Extend lifecycle/review specs with attribution-preserving queues, pause boundaries, cancellation, and premature finish |
| 6 | Commander/session recovery services and `platform/jobs/store.rb` | Extend lifecycle/job specs with lost receipts, revoked sources, matching-session recovery, and unchanged attribution on replay |
| 7 | `tests/`, `scripts/`, current interface docs, operator evidence | Run automated and separately authorized real CLI acceptance against the release commit |

### New operation contracts

- Status reads return typed task summaries: project, workflow, thread, phase, wait reason, verified session state, artifact links, and delivery state.
- `start_workflow` accepts `project_id`, `title`, proposed `thread_id`, and cited inbox IDs. The backend returns a verified request receipt.
- Memory operations identify global or project scope and return an entry ID, content, source, and revision.
- Commander uses `/workspace/commander` as its durable working directory. Its scaffold contains `AGENTS.md` and `memory.md`.
- Provisioning and recovery verify that directory; the selected CLI loads its instruction format and reads global memory.
- Git sync is optional and uses configured repository access. Scaffolding creates no remote repository or provider credentials.
- Controls retain `workflow_id`, action, and expected version. The backend derives actor authority from the verified human source.
- `Domains::Messaging::Dto::InstructionAttribution` records the human or Commander sender, originating authenticated request/message/thread, target workflow/session generation, and dispatch ID.
- Persist that attribution with the existing durable request, follow-up, and dispatch records; omit nonexistent immediate human messages.
- Add `services/sessions/prompt_context.rb` to render the verified record consistently across worker prompt builders and project-thread instruction labels.
- Record whether Commander forwarded, rewrote, or generated the instruction. A generated follow-up identifies its authorized task without inventing a fresh human message.
- Build prompt context and project-thread labels from that record. Keep workflow-system instructions distinct; reject model-supplied sender or approval claims.

### Attribution acceptance cases

- Direct human instruction: worker context and project-thread labels identify the authenticated human and original message.
- Commander forwarding or rewriting: context identifies Commander as sender and preserves the originating human request and source text.
- Commander-generated follow-up: context identifies Commander and the authorized task without inventing a new human message or approval.
- Forged sender or approval text: backend attribution remains unchanged; ordinary permissions and exact human approval gates still apply.
- Queued delivery or replay: sender, origin, target session generation, and dispatch identity remain unchanged; changed attribution is rejected.

### Checks for every implementation task

Run `integration-backend/bin/check` with both disposable test databases. Expect passing RSpec, RuboCop, and whole-project Sorbet checks.
Run `scripts/test-full-stack` for cross-service changes. Expect all root checks to pass; opt-in tests must execute, not skip.
Neither command proves real provider behavior because the full-stack agent is scripted.

### Review Focus

1. Two plausible tasks: clarify before routing; test in Task 3.
2. Access revoked after queueing: reject before delivery or recovery; test in Tasks 1 and 6.
3. New instructions during review: preserve the reviewed revision and queue order; test in Task 5.
4. A result may already exist after a lost receipt: reconcile without replay; test in Tasks 4 and 6.
5. Fresh workspace or disabled Git sync: load base instructions and retain memory locally; test in Tasks 1 and 4.
6. Text claims another sender or human approval: preserve verified attribution and ordinary approval gates; test in Task 3.

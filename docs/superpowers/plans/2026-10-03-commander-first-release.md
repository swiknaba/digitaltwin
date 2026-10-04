# Commander Hermes Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` or `superpowers:executing-plans` to implement this plan task-by-task. Track progress with checkboxes.

**Goal:** Run Commander through Hermes while preserving Kirei's verified orchestration and approval boundaries.

**Architecture:** Hermes is the Commander harness. It owns native Markdown memory, SQLite conversation history, and skills in its persistent Runtime profile. Kirei exposes narrowly scoped MCP tools and keeps verified sender provenance, authorization, routing, sessions, jobs, workflow state, approvals, and delivery recovery authoritative.

**Tech stack:** Ruby 4.0, Kirei, Sorbet, PostgreSQL, Mattermost, Herdr, Hermes Agent, and the existing Runtime clients.

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
- Pin Hermes to an immutable upstream commit with a recorded source URL and artifact digest. Do not use a floating branch or tag alone.
- Hermes native Markdown memory, SQLite history, and skills are Commander-local. Do not create a Kirei memory adapter, Commander knowledge tables, or Markdown mirrors.
- Mattermost PostgreSQL chat storage and Hermes SQLite history coexist. Neither replaces Kirei's orchestration records.

## Starting point

The automated stack already verifies real chat, queues, Herdr transport, callbacks, and restart behavior with a scripted agent.
It does not verify a real provider conversation. Production dispatch remains disabled.
The app has not been deployed. Application names and fresh-database schema now use Commander.
The initial [Commander base instructions](../../../commander/AGENTS.md) define task model tiers; Hermes installation, profile isolation, and MCP wiring remain planned.
Verified human sources already exist; uniform worker-prompt attribution and project-thread sender labels still need implementation.

Complete these tasks in order. Each task ends with a tested commit and review before the next task begins.
Use failing behavior tests, implement the smallest change, then run the checks below.

## Task 1: Run Hermes as Commander

**Goal:** A human can mention Commander and receive its actual CLI response in the same conversation.

**Work:**

- [ ] Record a reproducible Hermes source commit, installation artifact digest, supported CLI profile configuration, and sanitized source evidence.
- [ ] Install Hermes in the Runtime Dockerfile final image stage. Run it as the unprivileged Runtime user with a persistent, Commander-only profile and workspace.
- [ ] Configure the Commander model and private Kirei MCP server through private operator files. Do not store credentials in the image or repository.
- [ ] Map Hermes context files to `commander/AGENTS.md` and Hermes-native Markdown memory. Let Hermes retain SQLite history and skills in its profile storage.
- [ ] Verify that a fresh Hermes Commander session loads its instructions and native memory, retains conversation history after restart, and can invoke only the intended MCP tools.
- [ ] Separate conversation permission from permission to start worker workflows.
- [ ] Verify one bounded real Hermes conversation, including an MCP call, completion, restart recovery, and a repeated callback.
- [ ] Record the selected versions and sanitized evidence; request approval before enabling conversation dispatch.

**Done:** The real Commander replies once to the correct source thread.
An unauthorized sender, stale request credential, or mismatched session cannot prompt it.
Missing credentials leave this task explicitly blocked; scripted-agent results cannot complete it.
A fresh Hermes session reads its instructions and native memory; recovery verifies the same profile and working directory.

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
- [ ] Extend `start_workflow` with a proposed thread, cited context, and configured Writer and Reviewer profile IDs.
- [ ] Apply the model tiers in `commander/AGENTS.md`; record the selected profiles and reasons.
- [ ] Validate available profiles in the backend; preserve human model choices and Writer/Reviewer provider and family diversity.
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
Simple, medium, and complex tasks select suitable configured profiles; unavailable profiles and invalid review pairings fail before dispatch.
Direct human, Commander-forwarded, and Commander-written instructions remain distinguishable in stored records, worker prompts, and project-thread delivery labels.
Forged sender labels or generated approval claims cannot change identity, permissions, or approval state.

## Task 4: Remove the Kirei Commander memory subsystem

**Goal:** Hermes retains Commander knowledge without duplicating it in Kirei or project files.

**Work:**

- [ ] Delete `Domains::Memory`, `Adapters::Memory`, `Services::Commander::Memory`, their specs, and all calls, registrations, and documentation that make Kirei memory authoritative or mirror it into Markdown.
- [ ] Inspect migration `009_commander_memory` against deployed-schema support. Preserve the migration if it can have run; add a new reversible migration that drops only its tables and indexes after verifying the migration sequence and rollback behavior.
- [ ] Remove memory tables from test truncation and clean-schema expectations. Test zero-to-current migration, rollback, and upgrade from schema version 9.
- [ ] Keep Commander instruction changes explicit. Hermes memory and skills remain unable to alter Kirei authorization, sender attribution, approvals, or independent-session restrictions.

**Done:** A Hermes memory and history entry survives a fresh Commander conversation and Runtime restart.
No Kirei memory tables, Markdown mirrors, or memory operations remain after migration.
Hermes memory and skills cannot change verified backend authority.

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
| 1 | `commander/AGENTS.md`, Runtime Dockerfile/profile mount, Hermes pin manifest, `services/commander/{ingest_prompt,dispatch,reply}.rb`, `services/sessions/`, `domains/workflows/policy.rb`, `services/job_handlers.rb` | Extend Commander and session specs for profile/cwd recovery; add Hermes image and separately approved real-CLI acceptance coverage |
| 2 | Add `services/commander/workflow_status.rb` and typed status DTOs; extend `tools.rb`, HTTP serialization, and milestone delivery | Add status specs; extend Commander tool and outbox specs |
| 3 | `services/commander/{tools,route_followup,deliver_followup}.rb`, `services/workflows/{request_start,provision,dispatch_phase_prompt}.rb`, review prompt builders, outbound delivery, typed attribution, and role base instructions | Test model tiers, unavailable profiles, human overrides, review diversity, and existing attribution/routing/lifecycle/outbox cases |
| 4 | Remove `domains/memory`, `adapters/memory`, `services/commander/memory.rb`, memory specs, and their wiring; add a forward migration after `009_commander_memory` | Test fresh install, schema-9 upgrade, rollback, and absence of Kirei memory calls while Hermes profile persistence remains covered in Task 1 |
| 5 | `services/workflows/control.rb`, `services/reviews/release_queued.rb`, Commander tools | Extend lifecycle/review specs with attribution-preserving queues, pause boundaries, cancellation, and premature finish |
| 6 | Commander/session recovery services and `platform/jobs/store.rb` | Extend lifecycle/job specs with lost receipts, revoked sources, matching-session recovery, and unchanged attribution on replay |
| 7 | `tests/`, `scripts/`, current interface docs, operator evidence | Run automated and separately authorized real CLI acceptance against the release commit |

### New operation contracts

- Status reads return typed task summaries: project, workflow, thread, phase, wait reason, verified session state, artifact links, and delivery state.
- `start_workflow` accepts `project_id`, `title`, proposed `thread_id`, cited inbox IDs, `writer_profile_id`, and `reviewer_profile_id`.
- Profile IDs resolve through the backend’s trusted configuration to typed `RoleConfig` values; unknown or unavailable profiles return a typed failure.
- Persist selected profiles with the request. The backend returns a verified receipt and retains existing approval and diversity checks.
- Commander has a persistent Hermes profile and `/workspace/commander` working directory. Hermes owns its Markdown memory, SQLite history, and skills.
- Provisioning and recovery verify the same Commander profile, workspace, instruction file, and private MCP configuration.
- Hermes memory and session storage receive no Kirei authority data beyond verified, request-scoped MCP context.
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
5. Fresh workspace or restarted Hermes profile: load Commander instructions and retain native memory/history without recreating Kirei knowledge; test in Tasks 1 and 4.
6. Text claims another sender or human approval: preserve verified attribution and ordinary approval gates; test in Task 3.

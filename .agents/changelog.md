
## 2026-09-30

- Added a reviewable Phase 0 implementation plan based on spec commit `6129059`, with interface validation gates and all 32 acceptance criteria mapped to evidence.
- Linked the plan from README and prepared an owner-authorized planning branch and draft PR; implementation and deployment remain outside scope.

## 2026-10-01

- Revised Phase 0 routing so each verified Campfire thread owns one workflow and ordinary messages continue in an activated thread without repeat mentions.
- Required explicit thread-scoped `@worker finish` to close a delivered workflow and archive its Herdr session metadata; inactivity cannot close work.
- Aligned the specification and plan with Alpine-preferred images, Kirei CLI bootstrap, Ruby/Node pins, built-in health routes, and PostgreSQL jobs.
- Bound artifact approvals to Git commits and document paths; made Master configuration selectable and rejected duplicate starts in active threads.
- Removed planning status and local session history from docs and README; aligned the Phase 1 voice reference.
- Added workflow worktrees, an early integration spike, shared-type ordering, incremental schema constraints, and explicit correction/delivery transitions.
- Clarified collaborator authority, raw terminal access, callback limits, review diff scope, queued-message acknowledgements, and durable recovery.
- Planned a maintained Campfire Rails app with thread UI/API and authenticated events; added PostgreSQL search/schema/backup port and upstream maintenance checks.
- Defined separate Campfire and Kirei databases/roles on one PostgreSQL server, three application images, and retained Campfire Redis dependencies pending a backend decision.
- Clarified that Master operational chat and targeted emergency changes have no coding review cycle; ordinary project workflows retain their gates.
- Recorded the approved Campfire Redis sidecar, private service connectivity, persistence, and restart/restore checks.
- Routed Worker interview/progress replies through a session-bound Kirei callback and durable outbox while retaining visible bot/role identity.
- Defined thread-scoped pause as suppressing new dispatch while preserving current-step completion and callbacks; resume revalidates phase, revision, Runtime, and existing gates.
- Confirmed shared Master conversational context and operational access across fleet rooms, with separate Master sessions and private control/runtime data for independent fleets.
- Made Master-created workflow threads an optional Phase 0 convenience with verified/idempotent association; retained existing-thread starts and added a Phase 1 deferral path.
- Kept detailed updates in project threads and routed important summaries/blockers to configured Master chat with source links and event/destination deduplication.
- Defined worker sessions as LLM conversations, restricted reuse to the same workflow topic/role/configuration, and scoped fresh recovery to task state while retaining shared Master fleet context.

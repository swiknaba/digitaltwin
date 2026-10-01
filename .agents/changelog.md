
## 2026-09-30

- Added a reviewable Phase 0 implementation plan based on spec commit `6129059`, with interface validation gates and all 32 acceptance criteria mapped to evidence.
- Linked the plan from README and prepared an owner-authorized planning branch and draft PR; implementation and deployment remain outside scope.

## 2026-10-01

- Revised Phase 0 routing so each verified Campfire thread owns one workflow and ordinary messages continue in an activated thread without repeat mentions.
- Required explicit thread-scoped `@worker finish` to close a delivered workflow and archive its Herdr session metadata; inactivity cannot close work.
- Aligned the specification and plan with Alpine-preferred images, Kirei CLI bootstrap, Ruby/Node pins, built-in health routes, and PostgreSQL jobs.
- Bound artifact approvals to Git commits and document paths; made Master configuration selectable and rejected duplicate starts in active threads.
- Removed planning status and local session history from docs and README; aligned the Phase 1 voice reference.

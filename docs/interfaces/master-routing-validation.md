# Master routing increment

Baseline: local and freshly fetched remote `main` were
`f01b84665b723caa3ad9a266fb9d949caf262904` on 2026-10-02.
Both still used `agent-runtime`; no rename was present. This change leaves it untouched.
Implementation uses an isolated `build/master-context-routing` worktree.

## Implemented

- Ordinary human messages in explicitly configured Master chat enter durable routing.
- Verified project threads and recent same-human bindings resolve existing workflows.
  Conflicts/missing context ask for clarification; explicit selection cannot retarget an
  already recorded instruction. Parallel workflows retain separate threads/worktrees.
- Migration 007 records routing evidence, correlation, session generation and send state.
  Outbox acknowledgments say queued; no new workflow or session is created.
- Follow-ups recheck source, membership, phase and live pane identity. Review/pause and
  approval gates suppress sends. Only existing writing phases can receive prompts.
- Sends serialize per workflow; socket uncertainty and interrupted sends never auto-replay.
- Master-chat approvals require an exact human workflow/gate/commit command, current
  membership, latest approving review and clean matching Git revision. No gate advances.

## Evidence

`integration-backend/bin/check` runs on disposable PostgreSQL 18.6 and the existing
Ruby 4.0.7 amd64 dependency image: full RSpec, clean 001–007 migration/rollback,
91 RSpec examples passed; Layout/Lint/Security checks found no offenses and
shared-contract static typing passed. The 15 root contract tests also passed.
Socket fixture tests exercise real Unix sockets, correlation and target failures.
Concurrent PostgreSQL tests cover inbox deduplication and serialized sends.
A separate disposable offline Herdr 0.9.3 container passed its native health check;
the new adapter reached its actual socket and rejected a missing target. No CLI started.

Wire source: captured Herdr 0.9.3/protocol22 schema, SHA256
`9e2af207e9aa8183d4aeca5fde9cc48e7909bb40cdbd7cf21608a6d3ea78075b`.
`agent.get` and `agent.prompt` are captured operations; start/resume is not assumed.

## Remaining gates

Production `dispatch_allowed?` stays false. Positive CLI send/settled behavior,
authenticated chat, and selected Master MCP round trips remain unproved.
Master interpretation/bootstrap, thread/project creation, session lifecycle and review-release
coordination remain unfinished. Queued work requires these coordinators; no live delivery
is claimed. Their transitions must use the shared workflow advisory mutex. Existing
project review/pause `queued_messages` also need reconciliation with follow-up state.
Gemini CLI remains the specified default; Hermes/OpenClaw selection needs a separate
decision. No LiteLLM, credentials, paid requests or production changes were introduced.

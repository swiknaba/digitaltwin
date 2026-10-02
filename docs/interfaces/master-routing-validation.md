# Master routing increment

Baseline: local and freshly fetched remote `main` were
`f01b84665b723caa3ad9a266fb9d949caf262904` on 2026-10-02.
Both still used `agent-runtime`; no rename was present. This change leaves it untouched.
Implementation uses an isolated `build/master-context-routing` worktree.

## Implemented

- Master intake, verified thread/recent human context and evidence-grounded semantic selection.
  Conflicts clarify; parallel Master threads retain separate bindings and workflows retain worktrees.
- Migration 007 persists follow-up evidence, correlation, generation and delivery state. Migration
  008 adds request capabilities, workflow/thread requests and session lifecycle receipts.
- Verified bot thread creation, isolated worktree binding and trusted Writer/Reviewer reservation;
  Herdr workspace/create, agent/start, get/prompt and pane/close mapping. Uncertain effects block.
- Signed callback intake queues worker Git/socket verification. Review freezes exact commits,
  validates append-only reviewer changes, and queues durable release/corrective prompts.
- Exact human approvals advance only after latest review and unchanged approved artifact checks.
  Pause/resume and terminal cleanup retain version/revision binding and archive after positive stops.
- Typed stdio MCP uses private HTTP and expiring Controller request capabilities. Accessible
  context reads support interpretation; worker-originated independent sessions have no API.
- Same-conversation credential renewal, busy readiness deferral, idempotent reply receipt and
  exact same-human recovery for incomplete Master requests.

## Evidence

Full checks use disposable PostgreSQL 18.6 and the Ruby 4.0.7 amd64 dependency image: RSpec,
clean 001–008 migration/rollback, Layout/Lint/Security and shared-contract static typing.
Fixtures cover concurrency, review release/rollback, credential expiry/replacement, callback
roles/generations, authoritative context, Master request scope, stdio MCP and actual Git trees.
Counts and final independent review outcome are recorded in the PR after the final rerun.

Captured Herdr 0.9.3/protocol22 schema SHA256:
`9e2af207e9aa8183d4aeca5fde9cc48e7909bb40cdbd7cf21608a6d3ea78075b`.
Actual Unix-socket fixtures validate get/prompt/start/close envelopes. A disposable offline
Herdr container passed health and actual missing-target rejection; no CLI/provider started.
This is not positive CLI send/settled or selected Gemini MCP evidence.

## Remaining gates

`dispatch_allowed?` stays false. Authenticated chat, actual role CLI lifecycle/settled behavior
and selected Master MCP roundtrip remain unproved; operator profiles/credentials are not supplied.
No provider login, paid request, infrastructure change, Hermes/OpenClaw or LiteLLM was introduced.
Uncertain thread/runtime effects require operator reconciliation; no blind resend is implemented.
New project enrollment, verified PR delivery/done transition, broader Git/deployment/destructive
MCP tools and live Task 6–10 acceptance remain outside this bounded increment. The draft is not
an enabled fleet or completion of all Phase 0 workflows. Preserve those evidence/code gaps.

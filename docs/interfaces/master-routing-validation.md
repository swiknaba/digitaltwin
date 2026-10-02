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
- Authenticated session-capability callback intake queues worker Git/socket verification. Review freezes exact commits,
  validates append-only reviewer changes, and queues durable release/corrective prompts.
- Exact human approvals advance only after latest review and unchanged approved artifact checks.
  Pause/resume and terminal cleanup retain version/revision binding and archive after positive stops.
- Typed stdio MCP uses private HTTP and expiring Controller request capabilities. Accessible
  context reads support interpretation; worker-originated independent sessions have no API.
- Same-conversation credential renewal, busy readiness deferral, idempotent reply receipt and
  exact same-human recovery for incomplete Master requests.

## Evidence

Full checks use disposable PostgreSQL 18.6 and the Ruby 4.0.7 amd64 dependency image: RSpec,
clean 001-008 migration/rollback, Layout/Lint/Security and shared-contract static typing.
Fixtures cover concurrency, review release/rollback, credential expiry/replacement, callback
roles/generations, authoritative context, Master request scope, stdio MCP and actual Git trees.
Final backend check passed 132 examples (127 main +4 migration helper +1 clean migration),
87 files without lint offenses, and shared-contract static typing. Root contract tests passed 15; six opt-in live Compose tests were skipped.
Client provenance/staging passed 2 tests. Independent read-only review found no remaining material
code issue after durable release, cleanup, renewal, busy readiness and FIFO fixes.

Captured Herdr 0.9.3/protocol22 schema SHA256:
`9e2af207e9aa8183d4aeca5fde9cc48e7909bb40cdbd7cf21608a6d3ea78075b`.
Actual Unix-socket fixtures validate get/prompt/start/close envelopes. A disposable offline
Herdr container passed health and actual missing-target rejection. The new adapter also passed
actual workspace.create (including env), pane.close and unfiltered pane.list presence/absence
against Herdr0.9.3. No CLI/provider started.
The built Runtime image passed installed stdio MCP and artifact callback HTTP fixtures with external
networking disabled. Client provenance is frozen at backend commit
`68823ec0288270453ec502b5772c4d776d9d227f`; image ID
`sha256:fcb943cde87ee17c794833272428caeed80a502a7e65fe31b7015e615ae49c4f`.
This local image was not published.
This is not positive CLI send/settled or selected Gemini MCP evidence.

## Remaining gates

`dispatch_allowed?` stays false. Authenticated chat, actual role CLI lifecycle/settled behavior
and selected Master MCP roundtrip remain unproved; operator profiles/credentials are not supplied.
No provider login, paid request, infrastructure change, Hermes/OpenClaw or LiteLLM was introduced.
Uncertain follow-up outcomes have exact original-human delivered/discard reconciliation. Lost
thread receipts recover only against verified bot roots; session receipts recover only against exact
runtime identity or authoritative pane absence. No external operation is replayed. Review callbacks
can reconcile uncertain review dispatch using exact Git/runtime evidence. See
[minimum setup and acceptance](master-routing-setup.md).
New project enrollment, verified PR delivery/done transition, broader Git/deployment/destructive
MCP tools and live Task 6-10 acceptance remain outside this bounded increment. The draft is not
an enabled fleet or completion of all Phase 0 workflows. Preserve those evidence/code gaps.

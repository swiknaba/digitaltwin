# OpenCode Commander validation record

## Current boundary

Commander is a bundled OpenCode UI extension that opens beside the current
project session while retaining one global Commander conversation. It uses
existing sidecar client APIs to load, stream, prompt, interrupt, and reconnect
that session; it has no custom socket, proof broker, private HTTP API, panel
control plane, or test-harness flag. First use requires an operator-managed
neutral workspace and Commander agent, never a focused project's values.

Normal continuation uses a persisted Commander decision lookup for exact recorded
OpenCode provenance (runtime/project/session/message), then uses the ordinary
authenticated session API. The main process owns existing endpoint headers.
Renderer code, project configuration, Kirei rows, and MCP tool inputs never
receive those headers.

Kirei FutureTasks uses the same normal OpenCode prompt/message endpoints with an
operator-selected session and mounted authorization file. Its deterministic input
ids preserve delivery, reconciliation, disposition-outbox, cancellation, and
one-time successor idempotency. It fails closed when that configuration is
absent.

## Reproducible source evidence

- Pin: OpenCode \`v2.0.27\`,
  \`1f4d07a4a519185955ae8ab2ea3607805509e386\`.
- \`prepare-opencode.sh\` verifies the pin and reviewed bridge source manifest,
  then applies the maintained patch sequence to a clean checkout.
- A fresh preparation and \`git diff --check\` completed on 2026-10-14.
- Official Bun 1.4.2 frozen install completed in 83.67 seconds (2,397 packages)
  in a read-only-source Linux Docker setup; GUI typecheck then exited 0. The
  extension-host and graph Playwright component suites passed 25/25 with the
  same pinned source and Playwright Linux dependencies.
- Bridge continuation tests include a controlled local OpenCode-compatible API:
  they cover persisted provenance across restart, exact route selection,
  restart/retry identity, 409 digest readback, missing source rejection,
  changed-body conflict, and transient versus authorization failures.
- Kirei \`bin/check\`: 19 examples passed, 0 failures; RuboCop inspected 66 files
  with 0 offenses; whole-project Sorbet reported no errors.

## Remaining operator validation

No live credentials, user-global configuration, or desktop instance was changed
for this record. A real operator must still supply OpenCode authorization and an
exact destination session, then validate a live desktop continuation and a due
task against their authorized OpenCode server. Those are production-operational
checks, not source or container evidence.

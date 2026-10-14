# Commander OpenCode continuation

This package contains only the typed, normal OpenCode-session continuation
boundary. It does not start a socket, host a private HTTP service, mint proofs,
or deserialize runtime functions from JSON.

`OpenCodeSessionContinuation` accepts an exact recorded
`OpenCodeMessageProvenance`, verifies that exact session and source message with
the existing authenticated OpenCode API, then submits one ordinary session input
with `{ fromCommander: true }` metadata. The main process supplies the existing
OpenCode endpoint and authorization headers; the renderer, project
configuration, and Kirei persistence never receive them.

The deterministic input id is derived from runtime, project, session, source
message, and request id. It deliberately excludes text: a changed-body retry
addresses the same OpenCode input and a conflict fails closed instead of
admitting a second input. Transient failures are returned as `uncertain` for the
caller to reconcile or retry with the same id.

Run the focused checks:

\`\`\`sh
npm test
npm run typecheck
\`\`\`

The scheduled Kirei delivery adapter uses the same ordinary OpenCode session
route independently; it has no dependency on this Node package or a local
bridge listener.

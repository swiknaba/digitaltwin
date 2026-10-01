# Runtime handoff — 2026-10-01

Baseline: `7889c1a64856d75267ae6030db1743517b6a1342`.
Branch: `build/agent-runtime`; ownership limited to `agent-runtime/`.

Implemented a digest-pinned Linux AMD64 Alpine image with UID/GID 10001, persistent
home/workspaces, real Herdr 0.9.3/protocol 22, four pinned CLIs, Wagglebot 0.3.0 and
the required GNU/search/Python baseline. All four unauthenticated CLI launches use
real `herdr agent start`; no fake CLI or provider request was used. Linux schema
matches the captured macOS schema. Codex's initial `unknown` remains uncertain.

Alpine passes installed versions and initial UI startup. Native provider execution
still needs test credentials; this evidence does not establish post-work idle.
Fixed actual login-shell PATH reset and non-root OpenCode cache ownership. The
upstream Wagglebot npm workspace dependency defect is documented; its original
published bundle is extracted unchanged with separately locked `skills`.

Checks run:

- Docker build for offline and named-context `with-callback` targets.
- `bin/test-image digitaltwin-runtime-with-callback:20261001`: all offline tools,
  versions, role login shells, exact schema, running Herdr health, same-UID socket
  from a second container, no privileges/capabilities/host mounts/public ports,
  restart persistence and Git common-directory/worktree checks passed.
- Real unauthenticated Codex/Claude/OpenCode/Gemini start, state, pane-read and
  workspace-close calls; initial ready observed, no prompt/authentication supplied.
- Backend-owned standalone client hash enforced in build. Ruby 3.4.9 stdlib passes
  HTTP fixture checks for exact path/generation/key/text/Bearer, 202/403 handling,
  no automatic retry and no credential/body output. This is not live Kirei delivery.
- Shell syntax and `git diff --check` passed.

Local callback image ID:
`sha256:b111e6bf94da9becec8e71fbded33f44d72da796bbe27700f5368730f1d2657c`.
It was built locally, not published as an OCI release digest. Image is about
2.16 GB uncompressed; native CLI packages account for most of its size.

Backend client source: `integration-backend/bin/digitaltwin`, artifact SHA256
`a062e47b3e196256e0ee5a75f63084645835072ac9bf6a9c0d73d41be0dcf7d1`.
Backend owner supplied stable uncommitted source; integrator must record its final
commit before release. It is not duplicated in the Runtime repository.

Integration proposals (no shared files edited): use `with-callback` target with a
single-file named `kirei-clients` context; mount shared `/run/herdr` for Runtime and
Kirei worker at UID10001. Socket `/run/herdr/herdr.sock` is upstream-enforced 0600.
Persist `/home/runtime` and `/workspace`; no Docker socket, privileged mode or root
host mount. Runtime command and health are in README. Use a private task network;
no public port publication. Kirei's Ruby4.0.7 application pin remains independent
of the >=3.1 callback interpreter. Integrator owns root Compose and shared docs.

Required gates still open: authenticated prompt/state/stop/crash/timeout for all
four CLIs, artifact-ready then settled Writer, actual role shell tool execution,
selected Master MCP with channel context, full callback→outbox→source-thread
slice, real company Wagglebot provisioning, provider login persistence, private
SSH/Tailnet and complete transitive/redistribution-license audit. Installed MCP
help is capability discovery only. Native SSH is packaged with operator-key
preflight but not running; no keys or access state were created. Task1 gates still
block dependent Tasks6–10. No Phase1 voice or later LiteLLM/review framework added.

The integrator should add root changelog/interface entries for these changes;
worker ownership prevents concurrent `.agents/changelog.md` or shared docs edits.

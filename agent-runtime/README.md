# Agent Runtime

Non-root Linux AMD64 image containing Herdr 0.9.3, Codex, Claude Code, OpenCode,
Gemini CLI, xAI Grok Build, Hermes Agent, Wagglebot, OpenSSH, Ruby for the standalone callback, and the required
shell/Python tools. This component owns image packaging and local runtime tests.
Kirei owns session/workflow logic and callback/MCP source.

## Why this exists

Herdr provides one terminal/session interface for the installed agent CLIs, while Wagglebot
provisions their shared instructions. Keeping them in a separate deployable lets
Kirei's web and job processes restart without discarding agent terminals or their
persistent home. We could replace Herdr if another runtime proves the required
start/prompt/state/stop and settled-state contracts; we could remove this deployable
if agents move to an execution service that meets the same persistence, private
access, callback, and tool requirements.

## Build and local checks

Build context is **agent-runtime/**, not the repository root. No host home, login
state, signing material, or other component source is copied into the image.

```sh
docker build --platform linux/amd64 -t digitaltwin-runtime-worker:20261001 agent-runtime
agent-runtime/bin/test-image digitaltwin-runtime-worker:20261001
```

`test-image` uses unique disposable container names/anonymous volumes, no published
ports, UID/GID 10001, dropped capabilities and `no-new-privileges`. It runs real
installed version/schema checks, both login-shell configurations, functional tool
fixtures, a second-container socket check, and home/workspace restart checks. It
removes only its own containers and volumes. Recorded checks ran in Linux AMD64 containers under emulation on macOS ARM64.
This is a component test, not Phase 0 acceptance or a production deployment.

`bin/cli-startup-probe.py` runs **only in a disposable empty Runtime home**, with a
running Herdr server and no provider credentials. It creates/closes test workspaces
and starts the actual installed CLIs, including Hermes and Grok Build. Grok Build is a distinct
Herdr worker CLI; Hermes remains the Commander harness and may independently select xAI as an
inference provider. No prompt or authentication is submitted. The
recorded initial ready/idle states do not prove readiness after model work. Its default set covers
all installed harnesses; `CLI_STARTUP_PROBE_KINDS` can select a comma-separated subset for a
bounded offline component test.

## Exact dependencies and Debian slim decision

`tools.lock.yml`, `apt-packages.lock` and `package-lock.json` record the selected
runtime release, package set, source revisions, and checksums/integrities. The base
is the official semver tag `node:22.23.2-bookworm-slim`; image references follow
the project's release-tag policy rather than requiring a digest in `FROM`. The
build records its resolved Debian package set in `installed-apt.txt` inside the
image. Refresh that evidence deliberately after checks; never substitute floating
application dependencies.

AgentsView v0.44.0's verified Linux AMD64 artifact requires glibc: it runs in
disposable Debian Bookworm and fails before startup in Alpine 3.23. The Runtime
therefore uses Debian Bookworm slim, which also keeps the exact Node 22.23.2 base
and standard Debian tooling. It installs the checksum-verified v0.44.0 archive,
its provenance, and its SPDX document. AgentsView stores `usage` archive content
only: transcript text, tool inputs/results, thinking text, and titles are excluded.
It reads only the four declared Runtime roots for Claude, Codex, Gemini, and
OpenCode. Other configurable filesystem providers are disabled; the packaged
configuration declares no remote host, HTTP listener, public URL, or proxy. The
checksum-verified Linux Herdr binary and all four real CLI version/startup checks
must pass again on this base. Claude continues to use system ripgrep
(`USE_BUILTIN_RIPGREP=0`). Live provider shell checks remain open.

The previous Alpine image measured about 2.16 GB uncompressed; native CLI packages
dominated it. The post-build evidence records the replacement image's compressed
and uncompressed sizes separately. Neither value is inferred from the slim base
image alone.

Grok Build is the official xAI `grok` binary. xAI publishes stable/alpha/enterprise
channels rather than a minor-line artifact URL, so this Runtime records the current stable build
and advances it only in a deliberate image rebuild. The default local Grok config disables its
background updater; an operator supplies `XAI_API_KEY` or completes the official login outside Git.
Herdr's packaged `grok` integration registers only its local session-state hook. The image and
tests never submit a prompt, authenticate, or contact a provider.

Wagglebot 0.3.4 publishes the staged, self-contained package tarball: its manifest
has no `workspace:*` runtime dependencies and its remaining runtime dependencies are
bundled. The image extracts the checksum-verified published tarball and exposes the
separately locked skills 1.5.23 through NODE_PATH. Version/help checks and a real
reference-setup provisioning flow are required before this Runtime pin is accepted.
No company configuration is invented or fetched at startup.

The callback interpreter is Debian Ruby, satisfying the coordinated stdlib client
minimum >=3.1. It does not replace Kirei's backend-owned Ruby 4.0.7 pin.
Herdr is Apache-2.0, Codex/Gemini Apache-2.0, OpenCode/Wagglebot MIT. Claude Code is
an explicitly required proprietary upstream CLI; its package terms must be retained
and reviewed for distribution. The npm lock records the complete dependency set;
a full redistribution/transitive-license audit remains a release gate.

## Startup, volumes and integration boundary

| Contract | Value |
| --- | --- |
| User/group | 10001:10001 (`runtime`), including the Kirei worker accessing the socket |
| Command | `herdr server`, foreground under tini |
| Health | `/opt/runtime/bin/runtime-health`; checks real running compatible 0.9.3/protocol 22 |
| Runtime home | `/home/runtime`; Herdr config/session metadata, Wagglebot, interactive provider state |
| Workspace | `/workspace`; `repos/` and `worktrees/<workflow-uuid>` on the same persistent volume |
| Shared task-local directory | `/run/herdr`; `HERDR_SOCKET_PATH=/run/herdr/herdr.sock` |
| Socket permissions | upstream-enforced 0600; same UID required; separate `herdr-client.sock` also present |
| Network/ports | outbound provider/Git access when configured; no published ports by default |

Empty named volumes inherit image ownership. Bind mounts must be prepared as UID
10001 by the integrator/operator; non-root startup fails on unwritable mounts.
Configuration and the supported Codex/Claude/OpenCode integrations are initialized
idempotently in the persistent home. Herdr background version/manifest checks are
disabled in the initial config. Updates require an explicit rebuilt/pinned image or
operator provisioning action; startup never updates Wagglebot/company repositories.
No shared UID/process layout isolates malicious agents from one another.

Herdr's exact Linux schema matches `contracts/herdr-v0.9.3.schema.json` semantically.
Its version-bound socket messages use `{id, method, params}` and return `{id,result}`
or `{id,error}`. Installed CLI commands return the same envelopes. Captured
`workspace create`, `agent start`, `pane get/read`, `workspace close` and snapshot
commands use the real binary, not fabricated adapter methods. `unknown` is uncertain
and cannot complete work or authorize review. Kirei owns the schema-bound adapter.

## Backend client packaging

The default `offline` target has no callback/MCP substitute. Once the backend owner
provides its standalone artifact directory, package the source unchanged:

```sh
docker build --platform linux/amd64 --target with-callback \
  --build-context kirei-clients=/absolute/path/to/backend-client-artifact \
  -t digitaltwin-runtime-with-callback:local agent-runtime
```

The named context contains exactly the eleven backend-owned files in `contracts/kirei-clients.json`:
`digitaltwin`, `digitaltwin-mcp`, `mcp.rb`, `server/tool_gateway.rb`, `http_tools.rb`, and the six
AgentsView-only usage bridge files. Source revision and SHA256 hashes
are pinned; staging and image build both verify them. They use Ruby stdlib and no app/DB bundle.
Run `scripts/prepare-callback-context` from the repository root before a combined build.
Never copy a backend worktree or secret directory as the build context.

`digitaltwin` accepts say/artifact-ready/review-ready/commander-reply. Session token-file/generation
capabilities authenticate callbacks; the separate current-request token file authenticates Commander tools
and replies. `digitaltwin-mcp` bridges stdio to private Kirei HTTP with typed schemas and verified human
request binding. Agents receive no Mattermost bot credentials. Packaging is implemented; actual selected
Hermes MCP and CLI lifecycle/settled evidence remain open, and backend dispatch stays disabled.

### AgentsView usage reports

AgentsView is a local aggregate-reporting dependency, not a Runtime web service.
`RUNTIME_USAGE_TIMEZONE` defaults to `UTC` and must be an IANA timezone. The
Commander adapter first proves the live request capability, accepts calendar dates only, runs a local sync, then uses the
pinned executable in offline report mode. It accepts inclusive `today`,
month-to-date, `last_days` from 1 through 90 (including today), and custom
`from`/`to` ISO dates. Exact-hour or arbitrary command requests are rejected.

The Runtime owns and replaces its AgentsView configuration on each start, and
the MCP compares that image-owned file before each report: it permits only the
four listed local directories and rejects persisted or post-start remote-host
or listener configuration. It never creates the source directories; missing or
symlinked roots make the MCP request fail closed instead of reporting a
misleading zero. For an operator SSH session, use the same date-bound interface without copying
session data out of the Runtime:

```sh
agentsview usage daily --json --offline --no-sync --breakdown --timezone UTC --since 2026-10-06 --until 2026-10-06
agentsview usage daily --json --offline --no-sync --breakdown --timezone Europe/Berlin --since 2026-10-01 --until 2026-10-06
agentsview usage daily --json --offline --no-sync --breakdown --timezone UTC --since 2026-09-29 --until 2026-10-06 --agent codex
agentsview usage daily --json --offline --no-sync --breakdown --timezone UTC --since 2026-09-01 --until 2026-10-06
```

The one Commander tool is `get_usage`. Its response labels reported zero cost as
`reported`; computed catalog pricing as `estimated_api`; a mixed source as
`mixed`; unpriced token rows as `partial_estimate`; and absent pricing or usage as
`unavailable`. It includes the range, local-sync freshness, and pricing-table
metadata so a caller does not mistake unknown cost for zero.

No AgentsView UI is enabled or mapped by Compose. If an operator explicitly needs
a private diagnostic UI, run it in the foreground bound to loopback and tunnel it
over the already approved private SSH path: `agentsview serve --host 127.0.0.1
--port 8080 --no-browser`, then `ssh -L 8080:127.0.0.1:8080 runtime-host` from
the operator workstation. Binding it to Tailnet or any non-loopback interface
requires a separate infrastructure/authentication review.

## Explicit provisioning and private terminal access

Run as the runtime user: `runtime-provision connect <company-git-url>`, then
`runtime-provision company-update`; per project use `project-init <path>` followed
by `project-update <path>`. These wrappers map to supported Wagglebot commands and
restrict project paths to the real workspace roots. Provider login is an operator's
interactive terminal task and is never automated through Mattermost or image build.

OpenSSH is installed. `bin/runtime-ssh` is an opt-in foreground process using
`config/sshd_config` on port 2222. It requires operator-supplied readable
`/run/runtime-ssh/ssh_host_ed25519_key` and `$HOME/.ssh/authorized_keys`; it generates
no keys. Infrastructure must supervise this process with Herdr and route it only
through the private Tailnet with no public port publication. Non-root sshd login,
capability needs, Tailnet attachment and external rejection remain untested until
operator material is supplied. Do not claim terminal access is delivered from an
installed SSH binary alone. Direct terminal input is unsupervised and can invalidate
Kirei review exclusion. Production networking/keys/backup ownership stays external.

## Evidence and remaining gates

See `evidence/` for the real offline suite, Linux server status, socket/restart tests
and sanitized unauthenticated startup responses. All four `agent start` calls
returned `interactive_ready=true`; Codex state was `unknown`, others `idle` at the
initial welcome/configuration UI. No model calls occurred.

Still required: authenticated four-CLI prompt/state/stop and crash/timeout checks;
Writer artifact-ready then truly settled handshake; actual Writer/Reviewer tool
execution; selected Commander MCP round trip with verified source channel; full source-thread callback delivery; company provisioning; provider login
persistence; private SSH; complete license audit. The required Task 1 evidence still
blocks dependent Tasks 6-10 and is not cleared by these component checks. LiveKit
stays in Phase 1; future LiteLLM/review frameworks are excluded.

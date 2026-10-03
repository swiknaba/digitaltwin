# Agent Runtime

Non-root Linux AMD64 image containing Herdr 0.9.3, Codex, Claude Code, OpenCode,
Gemini CLI, Wagglebot, OpenSSH, Ruby for the standalone callback, and the required
shell/Python tools. This component owns image packaging and local runtime tests.
Kirei owns session/workflow logic and callback/MCP source.

## Why this exists

Herdr provides one terminal/session interface for four agent CLIs, while Wagglebot
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
and starts the actual four CLIs. No prompt or authentication is submitted. The
recorded initial ready/idle states do not prove readiness after model work.

## Exact dependencies and Alpine decision

`tools.lock.yml`, `.nvmrc`, `apk-packages.lock` and `package-lock.json` record exact
versions, source revisions, checksums/integrities and the base digest. Only Alpine
3.23 main/community packages are used. Package revisions may disappear from the
stable mirrors; refresh the manifest deliberately after checks, never fall back to
floating versions. `installed-apk.txt` inside the image records the resolved set.

The checksum-verified Linux Herdr binary and all four real CLI version/startup
checks pass on musl. Alpine's login profile resets PATH, so the image installs
`/etc/profile.d/runtime.sh` to give both roles the pinned tools. Claude uses system
ripgrep (`USE_BUILTIN_RIPGREP=0`) and pinned libgcc/libstdc++. No glibc fallback is
required by the tested offline commands. Live provider shell checks remain open.
The measured image is about 2.16 GB uncompressed: native CLI packages dominate it.

Wagglebot 0.3.0's published npm manifest contains `workspace:*` dependencies and
ordinary `npm install wagglebot@0.3.0` fails with `EUNSUPPORTEDPROTOCOL`. The image
extracts its checksum-verified, **unmodified published tarball**, whose dist bundle
contains those internal modules, and exposes the separately locked skills 1.5.23
through NODE_PATH. Version/help checks pass. Company provisioning against a real
operator repository remains open; no company configuration is invented or fetched
at startup. Revisit this packaging workaround after upstream repairs its release.

The callback interpreter is Alpine Ruby 3.4.9, satisfying the coordinated stdlib
client minimum >=3.1. It does not replace Kirei's backend-owned Ruby 4.0.7 pin.
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

The named context contains exactly the four backend-owned files in `contracts/kirei-clients.json`:
`digitaltwin`, `digitaltwin-mcp`, `mcp.rb`, and `http_tools.rb`. Source revision and SHA256 hashes
are pinned; staging and image build both verify them. They use Ruby stdlib and no app/DB bundle.
Run `scripts/prepare-callback-context` from the repository root before a combined build.
Never copy a backend worktree or secret directory as the build context.

`digitaltwin` accepts say/artifact-ready/review-ready/master-reply. Session token-file/generation
capabilities authenticate callbacks; the separate current-request token file authenticates Commander tools
and replies. `digitaltwin-mcp` bridges stdio to private Kirei HTTP with typed schemas and verified human
request binding. Agents receive no Mattermost bot credentials. Packaging is implemented; actual selected
Gemini MCP and CLI lifecycle/settled evidence remain open, and backend dispatch stays disabled.

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

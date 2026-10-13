# OpenCode Commander Gate 1 evidence

**Status:** The unmodified OpenCode `v2.0.27` plugin contract failed Gate 1. The
approved maintained UI patch now supplies a source-level Commander control surface,
but it has not yet been compiled or live-verified and does not provide the required
trusted bridge capability. The user has authorized an isolated, dependency-free
Commander bridge core while the patched Gate is investigated. The repository now
includes source-level Kirei FutureTasks adapters, a native MCP host, and a tested
private Kirei-to-Commander delivery/disposition contract. Those are bounded source
and disposable-container checks, not a live operator identity/runtime deployment.
Do not claim Gate 1 passes until the patched compile, security, and live checks pass.

## Authorized isolated bridge core (2026-10-13)

`commander/bridge/` now contains the typed bridge core and deterministic tests for
one persisted Commander conversation, monotonic stream cursor/event replay
handling, reconnect catch-up, steering/cancellation boundaries, and a consume-once
user-, conversation-, and action-bound capability interface. `FileConversationStore`
persists only conversation/replay metadata with mode `0600`; capability
presentations and runtime credentials are neither stored nor accepted from project
configuration. The test suite passes with Node 22's type-strip runner.

This is deliberately an adapter seam, not a desktop trust claim: production still
needs an operator-controlled verifier that atomically validates audience, actor,
conversation, expiry, and nonce replay, plus a reviewed desktop main-process path
that obtains the short-lived capability without exposing it to project code. The
source-level UI patch remains a control shell until that path and the upstream
TypeScript build complete.

## Inspected release

| Evidence | Result |
| --- | --- |
| Installed desktop CLI | `/Applications/OpenCode.app/Contents/Resources/opencode-cli` reports `opencode v2.0.27`; SHA-256 is `c60d9b61fe4ed3f1387efb6e101d81f052085ce64aada93d8e6937fbe80fbfa4`. |
| Global plugin state | The initial `opencode plugin list` reported `No plugins found` (npm/config plugins). The retained local probe is a separately loaded symlink at `~/.config/opencode/plugins/digitaltwin-commander-gate-probe.ts`; no project configuration was modified. |
| Plugin contract | The release CLI supports plugin list/add/check/update/remove. Its server OpenAPI exposes plugin listing/update and plugin RPC, while the published plugin documentation describes hooks and custom tools. |
| Session control plane | The same release's OpenAPI exposes `session.create`, `session.prompt`, durable session log streaming, inbox update/cancel (steering), and `session.interrupt`. It also exposes browser/app pairing. |
| UI extension surface | The inspected CLI/OpenAPI has no top-bar, toolbar, sidebar, view, or UI-registration operation. The released public plugin documentation describes server-side hooks/tools, not a desktop/web UI contribution API. |
| Live desktop observation | The running desktop application presents its ordinary session UI (project selector, session tab, prompt, model selector, and notifications) with no installed plugin and no visible Commander control. This is an observation, not proof that a supported global UI API is absent. |
| Live global-plugin probe | A symlinked local TypeScript plugin at `~/.config/opencode/plugins/digitaltwin-commander-gate-probe.ts` loaded successfully after a service restart. `GET /api/plugin` reports `id: digitaltwin-commander-gate-probe`, `source.type: local`, `state.status: active`, and only `features.server: true`. It exposes no UI/client/session/capability feature. |
| Installed contract mismatch | The first probe used the current public-doc named-function shape and was rejected. v2.0.27 requires a default definition with `id` plus `effect` or `setup`. The active probe uses the required default `setup` shape. Current web documentation therefore cannot substitute for release-bound evidence. |

The session controls demonstrate that a future bridge could own a durable OpenCode
session and implement prompt, stream, steer, and cancel without DOM automation. They
do **not** prove a supported global Commander control or a transparent branded
conversation UI, and must not be misrepresented as satisfying Gate 1.

## Reproduction and live result

The initial read-only inspection used the installed executable rather than a
downloaded or modified build:

```text
/Applications/OpenCode.app/Contents/Resources/opencode-cli --version
/Applications/OpenCode.app/Contents/Resources/opencode-cli plugin list
/Applications/OpenCode.app/Contents/Resources/opencode-cli api GET /openapi.json
```

The same release's `plugin --help` states that `plugin add` installs a package into
the active **global configuration**, and the CLI exposes no isolated configuration
flag. A live global-plugin experiment would therefore alter the active desktop
configuration before its clean removal. The approved probe created one retained
symlink only; it did not alter project configuration. This is why a server-only
plugin smoke test is not enough to close the gate: it proves loading only, not the
required supported UI/capability contract.

It also consulted the published [plugin documentation](https://opencode.ai/docs/plugins/)
and [command documentation](https://opencode.ai/docs/commands/) on 2026-10-12. The
probe source is repository-local at
`commander/opencode-gate-plugin/commander-gate-probe.ts`; its one global symlink is
intentionally retained for manual testing. No DOM selector, API key, paid model, or
provider login was used. The Mac locked before a post-load desktop accessibility
snapshot could be captured, and no remote-web UI was opened. Those observations are
not needed to establish failure: the active plugin's release-bound feature contract
is server-only and cannot supply any of the required UI/capability criteria.

## Required Gate 1 pass criteria

On a pinned upstream OpenCode version or its recorded maintained UI patch, record
one supported UI/capability contract that lets an operator-global extension:

1. add an always-visible global Commander control without a DOM selector;
2. open the one durable Commander conversation while preserving an active project
   session;
3. display and reconnect streamed external/session output under the Commander brand;
4. obtain a trusted user/conversation proof for the bridge without exposing a static
   credential to project configuration.

The proof must use a disposable project and an installed, version-pinned extension.
It must show duplicate/reconnect, steer, cancel, and stale-capability rejection. It
must not require a paid model or a provider login; a free configured model may be
used only if a model turn is genuinely needed.

## Decision

The smallest source-spec-consistent next step is an **upstream contribution or a
deliberately maintained small OpenCode UI patch** that supplies the four pass
criteria above. A global custom tool, a slash command, a plugin RPC, or an external
browser window alone is not an equivalent substitute because it does not provide the
required persistent top-bar control and transparent Commander surface.

### Selected maintained patch

The product owner selected the maintained UI-patch option on 2026-10-13. The
repository-owned artifact is
[`commander/opencode-ui-patch`](../../commander/opencode-ui-patch/). It applies only
to upstream tag `v2.0.27`, commit `1f4d07a4a519185955ae8ab2ea3607805509e386`.
The patch adds a bundled typed `commander` GUI extension, a titlebar control, a
session-preserving side panel, and a bundled `@digitaltwin/commander-bridge`
workspace package. It does not loosen the packaged extension manager's upstream trust
restriction and does not use DOM injection.

Patch SHA-256 values are
`0a94f441293ce1a2e69d0e6b62576ddcb1ca8763fede2c6b0b3610509335ec00`
for `0001-commander-gui-extension.patch` and
`4b068243461072cf42ecac0f493ff05eaf945e7d0af2dbff5f87d16f9ac49c2f`
for `0002-commander-panel-safety.patch`.
`9ce13b800aefaf9abc45c9ef118047dd2fc820cf32c51f49c6fa6d6184edc3a9`
is the SHA-256 for `0003-commander-bridge-ipc-seam.patch`.
`a5ac3d91e863e69eaf51507baff103000c7ea0575d65c37e17df48a68676e860`
is the SHA-256 for `0004-commander-bridge-workspace.patch`; the reviewed bridge
input manifest SHA-256 is
`d9294b084a6d31a45c34067cd96684bed8b529c81ba587ab81a04ecbaad46f29`.
`b9f30fcbb0a75976c30085d2b6ecc25a5084c7daa3c6ba15dde23ea8542d24ad`
is the SHA-256 for `0005-commander-panel-actions.patch`.
`4bbdeb6de21108a798bb102481a4ec10e70212099b531b6a68007ec5fbb77978`
is the SHA-256 for `0006-commander-desktop-bootstrap-harness.patch`; the reviewed
bridge input manifest SHA-256 is
`7ce2bd3ccdea20acbb0b8c5a87e8d1e61937c874269217b4ad15a12b3b10678e`.

`prepare-opencode.sh` requires a clean checkout at the exact pin, verifies the
bridge manifest, copies only `package.json`, `tsconfig.json`, and reviewed
`src/*.ts` source into the upstream `packages/commander-bridge` workspace, then
applies the patch sequence and checks the resulting diff. It refuses extra, missing,
or symlinked bridge inputs. It does not copy README files, user/project
configuration, credentials, runtime state, or persistent stores. The GUI extension
imports the package through a pinned `workspace:*` dependency and the lockfile
records that workspace resolution.

On 2026-10-13, the repaired `0006` patch was prepared again from a fresh detached
checkout at the pinned commit and passed `git diff --check`. In official
`oven/bun:1.4.2` Linux with source copied into the container filesystem, frozen
install completed 2,397 packages; bridge, GUI-extension, and desktop strict
typechecks all passed; the isolated desktop operator-context tests passed 3/3; and
the GUI-extension suite passed 177 with 1 skipped and 0 failed. The launcher
assertion/broker protocol is source and isolated-test evidence only: no live signer,
broker, or operator credential was provisioned, and this is not Gate 1 acceptance.

The patch applied cleanly to a fresh checkout of that exact commit on 2026-10-13 and
the resulting diff passed `git diff --check`. Upstream GUI-extension typecheck has
not run. Bun `1.4.2` on confirmed `darwin/arm64` repeatedly printed `Resolved,
downloaded and extracted [16]`, but failed to link the lockfile-required optional
`@typescript/native-preview-darwin-arm64` package into `node_modules`. The direct
`tsgo` entrypoint then reports that exact package as missing on disk. The same result
occurred with frozen/script-free install, `--force`, and Bun's `copyfile` backend.
The diagnostic process had established HTTPS downloads and was later suspended with
unread tool pipes; it was terminated before retrying. This is a dependency-linking
execution blocker, not a firewall block or a passing build result. No firewall
allowlist is currently required.

The exact official tarball was fetched through `npm pack`, matched the lockfile's
published SHA-512 integrity, and repaired the missing `tsgo` binary only in the
disposable source checkout. The checker then exposed the broader graph failure:
workspace imports such as `effect` also resolve to absent Bun-link targets. A distinct
frozen `--linker=hoisted` attempt reproduced that failure, so no more identical
whole-workspace retries are justified. The repaired checker did pass a strict isolated
typecheck of `commander/bridge/`; it does not validate the patched OpenCode GUI
extension. Manifests and lockfiles in the upstream checkout remained unchanged.

The diagnosis was then repeated with a fresh official npm-distributed `bun@1.4.2`,
a fresh detached worktree, and a fresh project-local Bun cache; all reproduced the
same 16-extraction partial graph. A one-package `effect@4.0.1` install with that same
toolchain completed and loaded successfully. The remaining failure is therefore
specific to this OpenCode workspace/dependency graph, not a global Bun version,
architecture, firewall, or cache problem.

On 2026-10-13, the existing local Docker daemon pulled the official
`docker.io/oven/bun:1.4.2` image at
`oven/bun@sha256:9114c058aeae42162ee16dd5084b95fe9473970bb6bcb5b232ab1630f0546895`.
No daemon, firewall, or security configuration was changed; the check used a
read-only disposable source mount and no secrets, privileged container, or host
networking. Because macOS bind-mount linking reproduces the partial graph, the
patched source was copied into the container's native Linux filesystem before its
install. There, Bun `1.4.2` completed the frozen install (2,494 installs across
2,928 packages), `@opencode/gui-extensions` typecheck exited `0`, and its tests
passed `177` with `1` skipped and `0` failed. This is Linux build/typecheck/test
evidence for the exact pinned patch only. It does not prove packaged macOS desktop
startup, the visible control, main-process bootstrap, or Gate 1's live interaction
criteria.

The bundled-workspace preparation was then repeated from a fresh checkout at the
same pin. The manifest verified every copied bridge file, `git diff --check` passed,
and the official Linux Bun `1.4.2` image completed a frozen, script-free install of
2,396 packages. `@digitaltwin/commander-bridge` strict TypeScript and
`@opencode/gui-extensions` typecheck both exited `0`; GUI tests passed `177` with
`1` skipped and `0` failed. Importing `@digitaltwin/commander-bridge` from the
dependent GUI workspace returned its configuration-free `not-configured` entrypoint.
The bridge's Node 22 test command separately passed all `17` tests. This confirms
the bounded packaging mechanism only; it still does not prove desktop startup or any
Gate 1 live interaction.

The patched panel invokes typed `open`, `send`, `steer`, `cancel`, and `reconnect`
main-process actions through `commanderPanelFromHostBootstrap` and displays only
sanitized event cursor/kind/text. Its IPC projection excludes conversation and
delivery identifiers, actor identity, proofs, origins, endpoint configuration,
credentials, and transport errors. In the absence of a desktop-host bootstrap it
fails closed at `not-configured`; IPC failure transitions to `unavailable` without
revealing the cause. The bridge's host-bootstrap test drives all five actions with a
one-use proof and verifies that no proof enters panel state. No upstream desktop host
currently calls `installHostOperatorBootstrap`, so this is a tested panel-to-bridge
invocation seam, not a claim that an external conversation or trusted capability
exchange is wired into OpenCode. Gate 1 has not passed.

The desktop patch now calls a main-process-only installer before built-in GUI
extensions start. It accepts only a `HostOperatorBootstrap` supplied by desktop
code; project configuration and renderer IPC have no install path. Normal launches
provide none and therefore remain closed. The explicit
`--commander-test-harness` switch starts only a loopback listener backed by random
in-memory one-use proofs and a synthetic runtime, then closes it on desktop quit.
It is a local test facility, not a production identity, credential, or operator
configuration path. The harness test covers panel open, prompt, emitted output,
reconnect, steer, and cancel. A packaged macOS Electron interaction run and a real
operator-owned identity/proof issuer remain required Gate 1 evidence.

`createOperatorHostBootstrap` is the deployment adapter: a trusted desktop host
supplies only a verified actor/conversation identity, bridge origin, and its
short-lived-proof exchange; the adapter creates the main-process panel and never
accepts those values from project or renderer code. The maintained desktop patch
loads an optional mode-`0600`, non-symlinked launcher context before a renderer
exists. It derives labels only from the opaque assertion payload, sends no labels to
the broker, and binds the assertion to its declared broker audience. The broker must
verify the signed assertion and derive identity before it issues an action-bound
proof. Invalid context or rejection leaves Commander unavailable without stopping
OpenCode startup. Provisioning the real signer, broker, and credentials remains an
operator approval step outside this repository.

The fresh Linux Bun 1.4.2 workspace check passed bridge, GUI-extension, and desktop
strict typechecks after this patch. The bridge Node 22 test suite passed locally.
Its package test command intentionally uses Node's type-strip runner, so invoking it
through Bun's workspace-script runner is unsupported and failed before executing the
suite; that does not replace the recorded Node result. Claude Code review was
requested for this boundary but its installed CLI was not authenticated (`/login`
required), so no Claude review is claimed.

On 2026-10-13, `prepare-opencode.sh` was rerun from a fresh detached checkout of
`1f4d07a4a519185955ae8ab2ea3607805509e386` after the panel-action patch. The
manifest verified every bridge input and the resulting upstream diff passed
`git diff --check`. In the official `oven/bun:1.4.2` Linux image (with the
read-only source copied into the container filesystem), frozen script-free install
completed 2,396 packages; bridge strict typecheck and GUI-extension typecheck both
exited `0`; the GUI suite passed 177 tests with one skipped and zero failed; and a
GUI-workspace import of `@digitaltwin/commander-bridge` returned its unconfigured
public entrypoint. The bridge's Node 22 test suite separately passed 19 tests,
including the host-bootstrap action path. This remains compile/test evidence, not
desktop startup or live Gate 1 evidence.

The source-level main-process seam and bridge core now include a typed user-action
transport with ephemeral per-action Authorization proofs. A proof binds its action,
the durable conversation, request id, and canonical command body; the bridge consumes
it once. The Node adapter accepts only capped JSON POST user-action routes and permits
only HTTPS or loopback destinations. Runtime-event ingestion is a separate typed,
authenticated channel and has no public user-action route. The local end-to-end test
uses only in-memory random one-use proofs and a loopback listener; it creates no
credential or persistent identity material. This remains source/test evidence only
until the patched OpenCode app compiles and a reviewed operator capability issuer plus
operator-owned runtime channel are wired into that app.

The bridge core now persists a generated active turn ID before calling the runtime.
Every runtime event, steer, and cancellation is bound to that ID; final output clears
it, and an event from an earlier turn is rejected rather than attaching to the next
prompt. Runtime I/O runs outside the controller's durable-mutation queue, with
prepare/complete-or-uncertain request records around the call. Deterministic tests
cover a slow prompt with concurrent cancellation, duplicate actions, body
substitution/replay, restart retention, and late old-turn events. A separate
runtime-only Unix socket adapter creates a mode-`0600` socket without replacing an
existing endpoint; its ephemeral local test authority is in-memory and writes no
identity or credential state. This is adapter/test evidence, not a production
operator-authentication claim. The patched OpenCode renderer still needs to invoke
the reviewed main-process transport before Gate 1 can pass.

On 2026-10-13, the maintained patch gained a Commander-specific Chromium
Playwright component fixture in
`packages/app/component-tests/commander-panel.spec.ts`.
`0007-commander-playwright-ui-fixture.patch` has SHA-256
`c770a50471d0fed99ff6cac7b201deed92b2e97a3e94b441e01a11b888354995`.
After fresh source preparation at the pinned `1f4d07a4a519185955ae8ab2ea3607805509e386`,
the official `oven/bun:1.4.2` Linux environment passed
`bun --filter @opencode/app typecheck`. The fixture then passed with the source
lockfile's Playwright `1.59.1` Chromium (`chromium v1217`) in 6.5 seconds. It
mounts the production Commander renderer through the real extension host and side
panel region, verifies the titlebar opens `commander:main` for the current project
session without replacing it, and renders open, send/stream, steer, reconnect, and
cancel behavior. Its typed IPC double exposes only the renderer contract's status,
event cursor, kind, and sanitized text; it has no conversation/user identity, proof,
endpoint, credential, or transport-error value. The passing run wrote
`commander-panel.png`; visual inspection recorded SHA-256
`755c028ca9099cba79e329fcf54bcfc5128bd98acafa5fa587ff642a34536467`.
The image is retained only as disposable test evidence, not committed to Git.
This is rendered component evidence, not a packaged Electron desktop launch,
`--commander-test-harness` interaction, real operator bootstrap, external runtime,
or Gate 1 pass.

On 2026-10-13, a disposable Linux/Xvfb Electron acceptance run used the explicit
`--commander-test-harness` switch against the same pinned, freshly prepared source.
The desktop startup installs the harness before creating its early renderer window;
the host-owned bootstrap is shared only within the main process so Vite's lazy
extension chunk observes it, with no renderer, project, environment, or IPC
configuration input. A real local project session opened Commander without replacing
that session. The rendered panel reported `Connected`; the run executed send,
synthetic stream/reconnect, steer, reconnect, and cancel, and retained the project
session. The captured Electron screenshot SHA-256 is
`9e2f3437fddbd982e221ad6894e55d11b083b3953f9093454329ee17a7c18b2a`.
This is desktop-harness evidence only: it uses random in-memory proofs and a local
loopback runtime, not an operator identity, production bridge endpoint, or external
Commander runtime. It therefore narrows the missing Gate 1 work but does not satisfy
Gate 1 by itself.

### Alternative only if the product specification changes

The smallest reduced-scope product would replace the top-bar/transparent-conversation
requirement with an operator-global `/commander` command that opens a separate,
explicitly branded Commander web route. OpenCode 2.0.27's global command and plugin
configuration can make this discoverable, while the OpenAPI session controls can
support the bridge behind it. This is a materially weaker UX: it does not preserve
the current project screen in one native OpenCode surface and does not meet the
current specification. Choose it only by an explicit product decision; it is not a
silent fallback.

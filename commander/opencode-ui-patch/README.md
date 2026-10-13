# Commander OpenCode UI patch

This is the maintained local patch required by the Commander feature specification.
It targets only upstream OpenCode `v2.0.27` at commit
`1f4d07a4a519185955ae8ab2ea3607805509e386`.

The patch adds a bundled `commander` GUI extension through OpenCode's typed GUI
extension SDK and a bundled `@digitaltwin/commander-bridge` workspace package. It
deliberately does **not** enable arbitrary extension archives in packaged builds:
that manager is disabled upstream because installed extensions can execute
main-process code and no packaged trust model exists.

## What it provides

- An always-visible `Commander` titlebar control.
- A typed Commander side-panel contribution that opens on the current project
  session without replacing it.
- A localized panel that invokes typed main-process `open`, `send`, `steer`,
  `cancel`, and `reconnect` actions and displays sanitized streamed event text.
- A source-whitelisted bridge workspace package that the GUI extension imports via
  a `workspace:*` dependency.

The IPC seam is fail-closed: without an operator-owned desktop host calling
`installHostOperatorBootstrap` before the GUI extension starts, it reports only
`not-configured` and exposes no action capability. With that bootstrap, all panel
actions are dispatched through `commanderPanelFromHostBootstrap`; the renderer sees
only status plus event cursor/kind/text. It never receives the conversation identity,
delivery IDs, identity, proof, origin, endpoint, credential, or transport error.
The repository includes no production OpenCode desktop-host integration that supplies
an operator bootstrap, so this remains a tested invocation seam rather than a Gate 1
pass or a live production bridge claim. The patched desktop's harness-only installer
runs before the early renderer window, and its host-owned process state is shared
across the lazy main-process extension chunks. Ordinary launches do not import the
harness or install a Commander bootstrap and remain closed; `--commander-test-harness` installs an
ephemeral loopback bridge with random in-memory proofs for local desktop acceptance
only.

Normal desktop startup always evaluates a trusted main-process bootstrap provider
before creating a renderer. The checked-in build installs no provider and therefore
remains `not-configured`; an embedding/operator may inject one before app readiness.
The provider is not read from project configuration, renderer IPC, or an environment
variable. The harness remains an explicit test-only provider path.

## Apply to the pinned source

```sh
git clone --branch v2.0.27 https://github.com/anomalyco/opencode.git opencode
git -C opencode rev-parse HEAD
sh /absolute/path/to/digitaltwin/commander/opencode-ui-patch/prepare-opencode.sh "$PWD/opencode"
```

The reported commit must equal the pin above and the target must be clean. The
preparation script verifies a SHA-256 manifest before it copies exactly the bridge
package manifest, strict TypeScript configuration, and reviewed `src/*.ts` files to
`packages/commander-bridge`; then it applies all seven patches, including the
workspace lockfile update. It copies no README, user/project configuration,
credentials, persistent store, or operator state. Keep the patched source and built
application outside this repository; this repository owns only the reproducible patch
and its evidence.

## Linux validation

OpenCode's Bun `1.4.2` dependency graph is verified in the official Linux image
`oven/bun:1.4.2`. Copy the prepared checkout into the container's native filesystem;
a macOS bind mount reproduces Bun's optional-package linker failure. For a fresh
validation:

```sh
docker run --rm \
  -v "$PWD/opencode:/source:ro" \
  oven/bun:1.4.2 \
  sh -lc 'set -eu
    mkdir /work && cp -a /source/. /work/
    cd /work
    bun install --frozen-lockfile --ignore-scripts
    bun --filter @digitaltwin/commander-bridge typecheck
    bun --filter @opencode/gui-extensions typecheck
    bun --filter @opencode/desktop typecheck
    bun --filter @opencode/gui-extensions test
    bun --cwd packages/gui-extensions -e "const bridge = await import(\"@digitaltwin/commander-bridge\"); if (bridge.unconfiguredCommanderBridgeStatus() !== \"not-configured\") throw new Error(\"bridge import failed\")"'
```

This validates source preparation, frozen workspace resolution, bridge strict
TypeScript, GUI-extension checks, and workspace-package import. Run the bridge's
Node 22 test command (`npm test` in `commander/bridge`) separately; OpenCode's root
`bunfig.toml` deliberately disables root-level Bun test discovery. These checks are
not a desktop startup or Gate 1 live-interaction result.

## Commander rendered-panel fixture

The maintained patch also adds one Chromium Playwright component fixture at
`packages/app/component-tests/commander-panel.spec.ts`. It mounts the production
Commander renderer through the real OpenCode extension host and side-panel region.
The fixture supplies an ephemeral typed IPC client that projects only the existing
renderer contract (`status`, event `cursor`, `kind`, and sanitized `text`): it has no
conversation identity, user identity, proof, endpoint, credential, or transport
error. It verifies the titlebar contribution opens `commander:main` for—not instead
of—the active project session, then renders `open`, `send`/stream, `steer`,
`reconnect`, and `cancel` interactions. The test writes an actual rendered Chromium
screenshot named `commander-panel.png` to its Playwright test result directory.

Run it against a freshly prepared source checkout in a disposable Linux container:

```sh
docker run --rm \
  -v "$PWD/opencode:/source:ro" \
  oven/bun:1.4.2 \
  sh -lc 'set -eu
    mkdir /work && cp -a /source/. /work/
    cd /work
    bun install --frozen-lockfile --ignore-scripts
    cd packages/app
    bunx playwright install --with-deps chromium
    bun run test:components -- \
      component-tests/commander-panel.spec.ts \
      --workers=1'
```

This is rendered component coverage, not an Electron desktop startup test: it does
not exercise the packaged desktop process, `--commander-test-harness`, a real
operator bootstrap, or an external Commander runtime. It therefore complements the
main-process harness tests without changing the Gate 1 evidence boundary.

## Electron harness acceptance

The same prepared checkout can be exercised in a disposable Linux/Xvfb container
with the explicit harness switch. Start the desktop from `packages/desktop` with
`--commander-test-harness`, open a local project session, click **Open Commander**,
then use the panel's **Send**, **Steer**, **Reconnect**, and **Cancel** controls.
The harness streams only synthetic local text and owns random in-memory proofs; it
does not read configuration or credentials from the renderer or project.

```sh
cd packages/desktop
XDG_CONFIG_HOME=/tmp/opencode-commander-config \
XDG_DATA_HOME=/tmp/opencode-commander-data \
xvfb-run -a bun run dev -- \
  --noSandbox --remoteDebuggingPort 9222 -- --commander-test-harness
```

`--noSandbox` is a Docker/Xvfb-only Chromium requirement for an unprivileged
container; it is not part of a product launch. A successful harness run proves the
patched Electron process and its local synthetic bridge path only. It remains
insufficient for production-operator connectivity or a complete Gate 1 pass.

## Maintenance

On every OpenCode update, first test the unmodified release. Rebase this patch only
when the release has no supported global Commander extension path. Regenerate
`bridge-source.sha256` from the exact reviewed inputs when bridge source changes;
the preparation script rejects extra or missing files. Record the new source commit,
patch hashes, UI check, and any trust-boundary changes in
`docs/interfaces/opencode-commander-gate.md`.

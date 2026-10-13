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
The repository does not yet include an OpenCode desktop-host integration that supplies
the trusted bootstrap, so this remains a tested invocation seam rather than a Gate 1
pass or a live production bridge claim. The patched desktop now invokes its
main-process-only installer before GUI extensions start. Ordinary launches pass no
bootstrap and remain closed; `--commander-test-harness` installs an ephemeral
loopback bridge with random in-memory proofs for local desktop acceptance only.

## Apply to the pinned source

```sh
git clone --branch v2.0.27 https://github.com/anomalyco/opencode.git opencode
git -C opencode rev-parse HEAD
sh /absolute/path/to/digitaltwin/commander/opencode-ui-patch/prepare-opencode.sh "$PWD/opencode"
```

The reported commit must equal the pin above and the target must be clean. The
preparation script verifies a SHA-256 manifest before it copies exactly the bridge
package manifest, strict TypeScript configuration, and reviewed `src/*.ts` files to
`packages/commander-bridge`; then it applies all five patches, including the
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

## Maintenance

On every OpenCode update, first test the unmodified release. Rebase this patch only
when the release has no supported global Commander extension path. Regenerate
`bridge-source.sha256` from the exact reviewed inputs when bridge source changes;
the preparation script rejects extra or missing files. Record the new source commit,
patch hashes, UI check, and any trust-boundary changes in
`docs/interfaces/opencode-commander-gate.md`.

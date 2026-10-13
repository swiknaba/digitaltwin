# Commander OpenCode UI patch

This is the maintained local patch required by the Commander feature specification.
It targets only upstream OpenCode `v2.0.27` at commit
`1f4d07a4a519185955ae8ab2ea3607805509e386`.

The patch adds a bundled `commander` GUI extension through OpenCode's typed GUI
extension SDK. It deliberately does **not** enable arbitrary extension archives in
packaged builds: that manager is disabled upstream because installed extensions can
execute main-process code and no packaged trust model exists.

## What it provides

- An always-visible `Commander` titlebar control.
- A typed Commander side-panel contribution that opens on the current project
  session without replacing it.
- A lazy, localized panel shell backed by a typed main-process bridge-status IPC.

The IPC seam deliberately reports only `not-configured`; it neither reads project
configuration nor sends a capability or runtime credential to the renderer. It does
not yet connect a bridge, persistent external Commander conversation, streaming,
reconnect behavior, or user/conversation-bound capabilities. Those are still
required to pass Gate 1 and must not be claimed from this UI patch alone.

## Apply to the pinned source

```sh
git clone --branch v2.0.27 https://github.com/anomalyco/opencode.git opencode
cd opencode
git rev-parse HEAD
git apply /absolute/path/to/digitaltwin/commander/opencode-ui-patch/0001-commander-gui-extension.patch
git apply /absolute/path/to/digitaltwin/commander/opencode-ui-patch/0002-commander-panel-safety.patch
git apply /absolute/path/to/digitaltwin/commander/opencode-ui-patch/0003-commander-bridge-ipc-seam.patch
```

The reported commit must equal the pin above. Use the upstream GUI-extension checks
from `packages/gui-extensions` before packaging. Keep the patched source and built
application outside this repository; this repository owns only the reproducible patch
and its evidence.

## Maintenance

On every OpenCode update, first test the unmodified release. Rebase this patch only
when the release has no supported global Commander extension path. Record the new
source commit, patch hashes, UI check, and any trust-boundary changes in
`docs/interfaces/opencode-commander-gate.md`.

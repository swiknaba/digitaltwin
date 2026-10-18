# macOS local app arm64 packaging spike

This document amends the V1 packaging design on the open PR 42 branch.  It is
kept on the implementation branch so that the PR's existing history does not
need to be rewritten just to begin the spike.

## Outcome and boundary

The spike creates an unsigned, project-local `DigitalTwin.app` under
`local/macos-local-app-spike/`. Its default app entry point starts the bundled
services, launches the nested patched OpenCode Electron application, waits for
that process, then stops the services when OpenCode quits. It is not a second
desktop UI. The real OpenCode Electron application is bundled as a nested
resource and is compiled from the maintained 46-patch Commander chain in a
fresh prepared checkout; the packager never copies a prior desktop artifact.

The production follow-up will move the same supervisor into OpenCode's existing
`ApplicationLifecycle` Effect layer.  That layer already owns `before-quit`,
`will-quit`, signal, and relaunch sequencing; adding a different process
manager now would make later lifecycle behaviour harder to verify.

The spike's resource graph is:

```text
DigitalTwin.app
  Contents/MacOS/DigitalTwin -> small lifecycle wrapper
  Contents/Resources/OpenCode.app -> patched native Electron desktop
  Contents/Resources/postgres -> PostgreSQL server tools
  Contents/Resources/ruby + kirei/vendor/bundle -> Kirei web and worker
  Contents/Resources/hermes -> Hermes source + its Python runtime
  Contents/Resources/bin/hermes-adapter -> compiled Bun adapter
```

All writable state is outside the app bundle, below the configurable absolute
`DIGITALTWIN_APP_DATA_ROOT`.  Its default is the sibling project-local
`local/macos-local-app-spike/data` directory.  The wrapper never reads or
creates `~/Library/Application Support/DigitalTwin`, and all build caches and
temporary directories are rooted at `local/macos-local-app-spike/`.

The nested OpenCode process receives a separate app-private home and XDG tree
below that same data directory. It does not adopt the user's ordinary OpenCode
state or local development sidecar. The wrapper creates a neutral Commander
workspace and seeds the shipped Commander agent only when it is absent; a
locally customized app-private agent is retained. It passes the bundled
loopback Hermes adapter endpoint and bearer only to Electron's main process,
which keeps it out of the renderer.

The wrapper uses independent loopback ports (15432, 13000, 18642, 13087, and
13086 for OpenCode's bundled sidecar by default), so it does not bind the
normal local stack's ports. Its packaged sidecar uses its own state root and
registration file, and shutdown verifies that registration points to an
app-private staged executable before terminating it. Each app launch generates
a fresh control token in memory for the loopback Hermes gateway and adapter;
it is not a provider credential and is never written to the app, profile,
logs, command arguments, or Git. The gateway token is removed before Electron
starts; the separate adapter token is consumed by Commander main-process code
and is never sent through the renderer bridge. The profile is created from the
credential-free tracked Commander template, so it cannot inherit the active
user's Hermes login state.

## Runtime provenance and licenses

The selected native versions follow the repository locks and source releases:

| Runtime | Version | Source / license decision |
| --- | --- | --- |
| Ruby | 4.0.7 | Verify the official source tarball with its published SHA-256 and compile it into the project-local toolchain; the backend lock requires Ruby 4.0.7. |
| PostgreSQL | 18.6 | Compile the official PostgreSQL source release used by `compose.yml`; it is under the PostgreSQL License. |
| Python for Hermes | 3.14.7 | Hermes requires Python `>=3.11,<3.15`.  The spike stages the existing project-local arm64 Python closure while a source-built closure is made reproducible; Python 3.14.7 publishes source hashes and is under the PSF license. |
| Hermes Agent | `3f62bc534296ece8d89b94bd20ddad0fc34791d3` | Stage the pinned project-local source, Python, and sealed dependency venv closure without profile or credential state.  Hermes Agent is MIT licensed. |
| OpenCode desktop | v2.0.27 / `1f4d07a4a519185955ae8ab2ea3607805509e386` | Build the maintained patch chain with its native Electron packaging config. |

Ruby's official download page identifies 4.0.7, its source tarball, and SHA-256.
PostgreSQL's official source listing supplies the 18.6 tarball and checksum
sidecar.  The toolchain script verifies both before compilation.  The first
Hermes package is intentionally a closure-stage test, not a claim that the
Hermes installer is redistributable: replacing it with a source-built Python
and locked wheels is a release gate before signing/notarization.  The staged
venv is mounted as Hermes's sealed payload environment and contains only locked
Python dependencies; the build explicitly excludes the user's Hermes home,
login files, state databases, and profile configuration.

The temporary minimum is macOS 13+ on arm64.  That matches PostgreSQL 18's
documented arm64 macOS support.  Signing, notarization, update hosting,
license-notice aggregation, and destructive-reset UX are later release
decisions and are deliberately not masked as spike validation.

## Build and verification

Prepare a clean pinned OpenCode checkout, then run the two project-local
packaging scripts:

```sh
git -C local/opencode worktree add --detach "$PWD/local/opencode-packaged-fresh" 1f4d07a4a519185955ae8ab2ea3607805509e386
sh commander/opencode-ui-patch/prepare-opencode.sh "$PWD/local/opencode-packaged-fresh"
(cd local/opencode-packaged-fresh && bun install --frozen-lockfile)
scripts/macos-local-app-spike-toolchain
DIGITALTWIN_OPENCODE_SOURCE="$PWD/local/opencode-packaged-fresh" scripts/macos-local-app-spike-build
```

The toolchain script fetches only the official Ruby and PostgreSQL source URLs,
checks their hashes, compiles arm64 resources, and installs the locked Kirei
gems into its staging directory.  Ruby 4.0.7 builds cleanly with Xcode 27.1 and
the macOS 27.0 SDK components installed; the local build verifies the resulting
`socket`, `strscan`, and `bigdecimal` extensions.  The build script packages the
adapter into a self-contained Bun executable, stages the Hermes closure without
any ignored profile data, rewrites its sealed virtual-environment launch paths
to bundle-relative Python, and compiles a fresh OpenCode app from the supplied
prepared checkout. The bundle includes `Contents/Resources/build-provenance.json`
with the pinned source revision, the prepared-source diff hash, and the
maintained-patch manifest hash.

For a candidate while the Finder app is running, select a separate generated
output and build root. The packager refuses to replace an existing default app
unless `DIGITALTWIN_REPLACE_DEFAULT_APP=yes` is explicit:

```sh
DIGITALTWIN_OPENCODE_SOURCE="$PWD/local/opencode-packaged-fresh" \
  DIGITALTWIN_APP_OUTPUT="$PWD/local/macos-local-app-spike/candidates/DigitalTwin-candidate.app" \
  DIGITALTWIN_APP_BUILD_ROOT="$PWD/local/macos-local-app-spike/build/candidate" \
  scripts/macos-local-app-spike-build
```

The staged Hermes payload excludes source tests, website, contributor material,
and Python bytecode caches. It retains the runtime source and sealed dependency
environment; further slimming requires a separately verified Hermes runtime
closure rather than deleting provider or gateway dependencies ad hoc.

Launching `DigitalTwin.app` normally runs the complete application with no
terminal setup or credential file: open
`local/macos-local-app-spike/DigitalTwin.app` in Finder. For a non-GUI service
verification:

```sh
local/macos-local-app-spike/DigitalTwin.app/Contents/MacOS/DigitalTwin verify
```

The launch-only control token does not grant provider access. A separately
configured approved provider is still required before a live Commander prompt
can run.

`verify` proves bundle-relative executable paths, Postgres readiness, Kirei web
and worker readiness, Hermes's unauthenticated rejection endpoint (no provider
call), adapter health, ordered shutdown, and a fresh restart.  It does not send
a model request, mutate the active profile, or launch the user's running stack.

The desktop acceptance build additionally uses the 0043--0046 maintained
OpenCode patches. They keep Electron's user data and XDG roots under the
app-private data directory, choose a fixed app-private sidecar port, and use
the bundled CLI's canonical registration name so the native renderer can reach
its own sidecar even while a normal OpenCode development service is running.
Patch 0046 gives the seeded Commander agent a bounded sidecar-discovery retry,
surfaces opening errors to the user, and uses the neutral native inverse titlebar
treatment instead of the previous green success pill.

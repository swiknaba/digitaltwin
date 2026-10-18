# macOS local app arm64 packaging spike

This document amends the V1 packaging design on the open PR 42 branch.  It is
kept on the implementation branch so that the PR's existing history does not
need to be rewritten just to begin the spike.

## Outcome and boundary

The spike creates an unsigned, project-local `DigitalTwin.app` under
`local/macos-local-app-spike/`.  Its wrapper is deliberately small: it starts,
checks, stops, and restarts the already-packaged services.  It is not a second
desktop UI.  The real OpenCode Electron application is bundled as a nested
resource and is built from the maintained 42-patch Commander chain in the
existing validation checkout.

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

The wrapper uses independent loopback ports (15432, 13000, 18642, and 13087 by
default), so it does not bind the normal local stack's ports.  It requires an
*existing* API-server token file when starting Hermes.  The token is read into
the child environment, never copied into the app, profile, logs, or Git.  The
profile is created from the credential-free tracked Commander template, so it
cannot inherit the active user's Hermes login state.

## Runtime provenance and licenses

The selected native versions follow the repository locks and source releases:

| Runtime | Version | Source / license decision |
| --- | --- | --- |
| Ruby | 4.0.7 | Verify the official source tarball with its published SHA-256; the backend lock requires Ruby 4.0.7.  The spike stages an exact existing arm64 4.0.7 closure only when the current Xcode cannot compile that source. |
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

Run the two project-local scripts in order:

```sh
scripts/macos-local-app-spike-toolchain
scripts/macos-local-app-spike-build
```

The toolchain script fetches only the official Ruby and PostgreSQL source URLs,
checks their hashes, compiles arm64 resources, and installs the locked Kirei
gems into its staging directory.  On the current Xcode 27 SDK, Ruby 4.0.7's
bundled `socket`, `strscan`, and `bigdecimal` extensions fail to compile against
the Darwin 27 headers.  For this local assembly spike only, pass an explicit
already-installed exact Ruby closure through `DIGITALTWIN_RUBY_STAGE_SOURCE`; it
is copied into the app and is not a runtime dependency.  A clean official Ruby
source build remains a release gate.  The build script packages the adapter into
a self-contained Bun executable, stages the Hermes closure without any ignored
profile data, and copies the already-built OpenCode app from the isolated
validation checkout.

For a run, pass an existing local API-server token file explicitly rather than
writing a new credential:

```sh
DIGITALTWIN_HERMES_API_TOKEN_FILE="$PWD/local/secrets/hermes-api-server-token" \
  local/macos-local-app-spike/DigitalTwin.app/Contents/MacOS/DigitalTwin verify
```

`verify` proves bundle-relative executable paths, Postgres readiness, Kirei web
and worker readiness, Hermes's unauthenticated rejection endpoint (no provider
call), adapter health, ordered shutdown, and a fresh restart.  It does not send
a model request, mutate the active profile, or launch the user's running stack.

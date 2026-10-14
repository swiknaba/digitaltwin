# Commander OpenCode patch

This maintained patch targets OpenCode v2.0.27 at
`1f4d07a4a519185955ae8ab2ea3607805509e386`. It adds a small Commander panel
and the reviewed `@digitaltwin/commander-bridge` workspace package.

Normal desktop startup needs no harness flag. The extension reads only the
already-configured sidecar availability in OpenCode's main process; it does not
load user configuration, make a second socket, or pass endpoint credentials to
the renderer. Missing sidecar context presents an unavailable state.

The bridge package is an exact-session continuation helper. Scheduled Kirei
delivery independently uses the same authenticated normal OpenCode session API.
Neither path uses the removed private Node bridge, proof exchange, panel control
plane, or synthetic desktop harness.

Prepare a clean checkout:

\`\`\`sh
git clone --branch v2.0.27 https://github.com/anomalyco/opencode.git opencode
sh /absolute/path/to/digitaltwin/commander/opencode-ui-patch/prepare-opencode.sh "$PWD/opencode"
\`\`\`

The script verifies the pinned revision and an allowlist SHA-256 manifest before
copying the bridge sources, then applies all patches. Empty reserved patch slots
are accepted deliberately so the reviewed seven-patch sequence remains stable.
It copies no configuration, credentials, persistent store, or operator state.

Validate a prepared Linux checkout with official Bun 1.4.2 for frozen install
and GUI/desktop typechecks. Use Node 22 for the bridge package's `tsgo` check;
the Bun image does not provide that launcher. These checks prove patch
preparation and compilation, not a live operator authorization or desktop
interaction.

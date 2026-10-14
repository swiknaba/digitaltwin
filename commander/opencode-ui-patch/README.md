# Commander OpenCode patch

This maintained patch targets OpenCode v2.0.27 at
`1f4d07a4a519185955ae8ab2ea3607805509e386`. It adds a small persistent Commander panel
and the reviewed `@digitaltwin/commander-bridge` workspace package.

Normal desktop startup needs no harness flag. The extension stores one Commander
OpenCode session identity in desktop extension storage. It creates, loads,
streams, sends to, interrupts, and reconnects that ordinary session through
OpenCode's existing client APIs. The same identity is used across project
switches, close/reopen, and desktop restart. It does not load user
configuration, make a second socket, or pass endpoint credentials through a
new renderer bridge.

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
copying the bridge sources, then applies all patches. The final reserved patch
slot remains accepted deliberately so the reviewed seven-patch sequence stays
stable.
It copies no configuration, credentials, persistent store, or operator state.

Validate a prepared Linux checkout with official Bun 1.4.2 for frozen install
and GUI/desktop typechecks. Use Node 22 for the bridge package's `tsgo` check;
the Bun image does not provide that launcher. These checks prove patch
preparation and compilation, not a live operator authorization, provider run,
or desktop interaction.

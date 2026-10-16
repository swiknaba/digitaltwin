# Commander OpenCode patch

This maintained patch targets OpenCode v2.0.27 at
`1f4d07a4a519185955ae8ab2ea3607805509e386`. It adds a persistent global
Commander dialog and the reviewed `@digitaltwin/commander-bridge` workspace
package.

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

Before first use, the desktop operator supplies the neutral Commander workspace
and agent shown in `operator.env.example` through the desktop launch environment.
Both values are required; the main-process extension rejects a missing or
relative workspace and never derives either value from the focused project. The
renderer receives only the validated session location and agent, never the
environment source or credentials.

The prepared checkout includes `run-opencode-commander.sh`. Copy and edit its
`commander.env.example` outside source control, then launch OpenCode through the
wrapper; it loads the operator file, validates the neutral workspace exists and
is absolute, validates the agent name, and exports only those non-secret values.

From the DigitalTwin repository root, prepare a clean, ignored local checkout:

\`\`\`sh
git clone --branch v2.0.27 https://github.com/anomalyco/opencode.git local/opencode
sh commander/opencode-ui-patch/prepare-opencode.sh
\`\`\`

The default target is `local/opencode`; pass an absolute checkout path only when
an operator deliberately needs a different location. The script verifies the pinned revision and an allowlist SHA-256 manifest before
copying the bridge sources, then applies all patches. The reviewed patch
sequence is currently twenty-one patches.
It copies no configuration, credentials, persistent store, or operator state.

For a local desktop walkthrough—including optional native-agent continuation and
FutureTasks validation—follow [the Commander local E2E guide](../LOCAL_E2E.md).

Validate a prepared Linux checkout with official Bun 1.4.2 for frozen install
and GUI/desktop typechecks. Use Node 22 for the bridge package's `tsgo` check;
the Bun image does not provide that launcher. These checks prove patch
preparation and compilation, not a live operator authorization, provider run,
or desktop interaction.

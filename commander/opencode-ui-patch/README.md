# Commander OpenCode patch

This maintained patch targets OpenCode v2.0.27 at
`1f4d07a4a519185955ae8ab2ea3607805509e386`. It adds a persistent global
Commander dialog, native composer, and Hermes-backed model picker.

Normal desktop startup preserves ordinary OpenCode project sessions. When the
separately configured local Hermes adapter is available, Commander submits to
its durable Hermes session through typed main-process IPC. The renderer receives
neither the bearer token nor the Hermes profile path; the local adapter requires
the private loopback bearer header from the trusted desktop process or Kirei.

Commander chooses one durable `{ providerID, modelID }` identity from the
Hermes-confirmed portion of OpenCode's native explicitly enabled model catalog.
Every model is hidden by default, including free and built-in models; the user
enables each model in native OpenCode settings. Those native visibility choices
remain the single persisted source of truth for Commander and Hermes worker
selection. The selection is not an
OpenCode session setting: the adapter stores it for Commander only and restores
it when the desktop process reopens. Hermes separately selects any project
worker from the enabled inventory for each new project session, using the user's
natural-language request only when they name a worker model. The packaged
launcher reads only an active native Anthropic key at process start and passes
it to its local Hermes child as ephemeral process environment; it never copies
the credential into Commander state, patch source, logs, or a second settings
store. Other Hermes authentication remains separately approved.

The active OpenCode continuation plugin owns exact-session follow-up bindings.
Scheduled Kirei delivery independently uses the authenticated normal OpenCode
session API. Neither path uses a private Node bridge, proof exchange, panel
control plane, or synthetic desktop harness.

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
an operator deliberately needs a different location. The script verifies the
pinned revision, then applies all patches. The reviewed patch sequence is
currently forty-seven patches.
It copies no configuration, credentials, persistent store, or operator state.

For a local desktop walkthrough—including optional native-agent continuation and
FutureTasks validation—follow [the Commander local E2E guide](../LOCAL_E2E.md).

Validate a prepared Linux checkout with official Bun 1.4.2 for frozen install
and GUI/desktop typechecks. These checks prove patch
preparation and compilation, not a live operator authorization, provider run,
or desktop interaction.

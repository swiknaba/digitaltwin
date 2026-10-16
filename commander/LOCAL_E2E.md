# Commander local end-to-end guide

This guide validates the patched OpenCode desktop app on one developer machine.
It is deliberately local: it neither deploys Commander nor changes a user-global
configuration unless the optional plugin steps are chosen explicitly.

## Prerequisites

- macOS, Bun `1.4.2`, Git, and the OpenCode desktop build prerequisites.
- An existing OpenCode provider/model configuration that can serve the named
  `commander` agent. Do not copy a provider key into this repository, the
  Commander env file, or a shell history.
- A local, absolute workspace that is distinct from the project opened in the
  desktop UI. It can be empty.

## Prepare and launch

Run these commands from the root of this repository. They use your existing
project checkout and leave it unchanged. The patch applies only to a separate,
fresh OpenCode checkout in the ignored `local/opencode` directory.

### 1. Patch a fresh OpenCode checkout

```sh
DIGITALTWIN_ROOT="$PWD"
git clone --branch v2.0.27 https://github.com/anomalyco/opencode.git local/opencode
sh "$DIGITALTWIN_ROOT/commander/opencode-ui-patch/prepare-opencode.sh"
cd local/opencode
bun install --frozen-lockfile
```

`prepare-opencode.sh` refuses an OpenCode checkout that is dirty, is at another
revision, or is already patched. To re-run it, remove only the
`local/opencode` checkout if you created it for this test, then start again.

### 2. Configure the environment

```sh
mkdir -p /tmp/digitaltwin-commander-workspace
cp commander.env.example /tmp/digitaltwin-commander.env
${EDITOR:-vi} /tmp/digitaltwin-commander.env
```

### 3. Launch

Run this from `local/opencode`:

```sh
sh ./run-opencode-commander.sh /tmp/digitaltwin-commander.env bun run dev:desktop
```

In the env file, set `DIGITALTWIN_COMMANDER_WORKSPACE` in `/tmp/digitaltwin-commander.env` to
`/tmp/digitaltwin-commander-workspace` and set
`DIGITALTWIN_COMMANDER_AGENT` to the identifier of an agent already declared in
your normal OpenCode configuration. The wrapper validates only the absolute
workspace and non-empty agent name. At reservation time the Commander main
process calls the authenticated sidecar's normal `/api/agent` endpoint for that
workspace and refuses to create or reuse state unless that agent is available.

The env file contains no credentials. Provider credentials, models, and the
agent declaration remain in the operator's existing OpenCode setup. If they are
not configured, the expected result is an unavailable/failed Commander panel,
not an attempt by this patch to provision a provider.

## Desktop acceptance path

1. Open any ordinary project session in the desktop app.
2. Open **Commander** from the title-bar contribution. It should create one
   neutral session in the configured workspace, not in the focused project.
3. Send a prompt. The normal timeline should stream the assistant response;
   **Stop** should interrupt that same session.
4. Switch projects, close and reopen Commander, then quit and relaunch through
   the same wrapper. Commander should retain the same neutral conversation
   identity and remain independent of the focused project.
5. To exercise recovery, stop the sidecar or make the stored session unavailable,
   then use **Reconnect**. The app recreates that exact reserved session ID with
   the configured workspace and agent.

The panel is not a provider test. A real response requires the already-configured
provider above; panel/session identity, reconnect, and visible streamed content
are covered in the checked-in component test.

## Optional native follow-up validation

This is an explicit operator-owned global plugin change. To enable the normal
OpenCode continuation plugin, choose a dedicated plugin directory and install
only symlinks there:

Run this from the root of this repository:

```sh
OPENCODE_GLOBAL_PLUGIN_DIR=/absolute/operator-owned/opencode/plugins \
  sh commander/opencode-gate-plugin/install-future-tasks-plugin.sh
```

Restart OpenCode, then ask the Commander session to start a native OpenCode
`subagent`. When it completes, the plugin appends a `Commander follow-up
reference` containing its decision ID. Invoke `commander_continue_agent` from
that Commander session with that `decision_id`, a new `request_id`, and the
follow-up text. The plugin resolves the recorded child session and sends the
ordinary OpenCode prompt to that exact prior session; it does not accept a
session ID from the caller.

## Optional FutureTasks validation

FutureTasks additionally needs an operator-configured
`digitaltwinFutureTasksEndpoint` and the operator-issued capability exchange.
Neither belongs in this checkout. With both already available, ask Commander to
call `future_tasks` with operation `create`, its supplied capability, a one-time
local timestamp with an explicit UTC offset and IANA timezone, and a short
check-in instruction. Record the returned task ID and version. When due, verify
that it appears as a check-in only; it must not start code, merge, or deploy.
Use that same ID/version for update or cancellation.

## Cleanup

Quit the development desktop app. Remove `/tmp/digitaltwin-commander.env`,
`/tmp/digitaltwin-commander-workspace`, and `local/opencode` only if they were
created for this test.
If the optional plugin step was used, remove only the two
`digitaltwin-future-tasks.ts` and `digitaltwin-commander-continuation.ts`
symlinks from the operator-owned plugin directory. Do not delete or modify an
existing user's global OpenCode configuration, providers, credentials, or
desktop storage as part of this guide.

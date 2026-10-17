# Commander local guide

Run this from the root of your existing DigitalTwin checkout. It prepares the
patched OpenCode source under this checkout's ignored `local/` directory; it
does not clone DigitalTwin or use a sibling checkout.

## Prerequisites

- macOS, Git, Bun `1.4.2`, and the OpenCode desktop build prerequisites.
- Your normal OpenCode provider/model configuration. Keep provider credentials
  in that existing OpenCode setup, not in this repository or its Commander env
  file.

The Commander workspace below is intentionally separate from the project you
open in OpenCode. It lives under this repository only to keep generated local
state together; do not open `local/commander-workspace` as a project.

## Prepare OpenCode

In a terminal at the DigitalTwin repository root:

```sh
REPO_ROOT="$PWD"
mkdir -p "$REPO_ROOT/local/tmp" "$REPO_ROOT/local/commander-workspace"
export TMPDIR="$REPO_ROOT/local/tmp"
export DIGITALTWIN_LOCAL_TMPDIR="$TMPDIR"

if [ ! -d "$REPO_ROOT/local/opencode/.git" ]; then
  git clone --branch v2.0.27 https://github.com/anomalyco/opencode.git "$REPO_ROOT/local/opencode"
fi

if [ ! -x "$REPO_ROOT/local/opencode/run-opencode-commander.sh" ]; then
  sh "$REPO_ROOT/commander/opencode-ui-patch/prepare-opencode.sh"
fi

cd "$REPO_ROOT/local/opencode"
bun install --frozen-lockfile
```

`local/opencode` is reused when it has already been prepared. The preparation
script only modifies a fresh OpenCode v2.0.27 checkout and stops on a dirty,
wrong-version, or partially prepared checkout. It never resets or deletes that
checkout; inspect it before deliberately replacing it.

## Configure and launch

The checked-in `.env.overmind` supplies the normal local Commander workspace
and agent. The first launch creates its workspace-scoped `commander` agent under
`local/commander-workspace/.opencode/agents/`. The managed `commander` agent is
seeded from `commander/commander-agent-baseline.md` when absent, or upgraded
only from the legacy generated default; a locally customized agent file is left
unchanged. Commander itself stores one provider/model identity from the native
OpenCode visible-model picker, including its model visibility preferences, and
never writes or reads provider credentials. An existing
`local/commander.env` remains an optional, ignored override for a deliberately
different workspace or agent.

Hermes Commander is separately local and opt-in. After the operator has approved
the control API, create `local/hermes/commander-profile/config.yaml` and the
owner-only `local/secrets/hermes-api-server-token`, then run
`scripts/local-hermes-profile`. The project-local Hermes source, tool store,
cache, lock root, and profile all live below `local/hermes/`; the gateway never
uses or updates an installation under the user's home directory.

Provision the pinned project-local runtime once with:

```sh
sh scripts/local-hermes-runtime-install
```

The bootstrap script reads the existing official Hermes installer only to create
the pinned runtime under `local/hermes/runtime/`; it redirects `HOME`, XDG state,
the Hermes tool store, and gateway locks to that project-local directory. It does
not change a user-shell startup file or a global Hermes installation.

When the owner is ready to configure Hermes authentication or a shared LiteLLM
route, open the project-local official picker with:

```sh
sh scripts/local-hermes-model
```

It reuses the local Hermes launcher while omitting the gateway control bearer;
its `HOME`, `HERMES_HOME`, caches, and runtime state remain below `local/hermes/`.
It is interactive and may write provider authentication there, so do not run it
until that configuration is approved. It is not a second Commander model picker:
Commander always uses its native OpenCode selection and locks that exact identity
for each Hermes run.

When those approved files and the project-local runtime are present,
`sh scripts/local-overmind` starts the loopback Hermes gateway and adapter with
the Kirei web service, worker, and patched OpenCode desktop. If Hermes is not
available, its supervised processes report the missing project-local dependency
and keep retrying while the rest of the local stack stays up; Commander remains
unavailable and never falls back to an ordinary OpenCode model. Starting the
control API does not select a model or make a provider call. The renderer never receives the adapter token;
the local worker reads it directly from the ignored owner-only file into its
process environment, never Kirei persistence or a tracked configuration file.

Start the full local stack from the DigitalTwin repository root:

```sh
sh scripts/local-overmind
```

This starts one patched OpenCode desktop (including its local sidecar), Kirei
web, and the Kirei worker. It uses the checked-in non-secret `.env.overmind`
and the existing host PostgreSQL on `127.0.0.1:5432`; it creates only the
dedicated `digitaltwin_local` and `digitaltwin_local_test` databases when they
do not exist.

The local launcher also creates one ignored, stack-local OpenCode plugin entry
under `local/opencode/.opencode/plugins/digitaltwin-commander-continuation/`. It is supplied as an
explicit additive OpenCode config, so normal user-global OpenCode configuration
remains available. It installs only `commander_continue_agent`; it does not read
or configure the pending sidecar service-registration credential.

The development launcher runs its own isolated sidecar on `127.0.0.1:3086`.
That avoids adopting or replacing an installed OpenCode service on its default
port; the app retains its own desktop session storage and still layers its
plugin configuration over normal user-global OpenCode configuration.

Local development and tests run directly on macOS through Overmind; Docker is
not part of this path. Remote deployment runs the complete stack in Docker. The
future self-contained ARM64 macOS `.app` will bundle the required Ruby, Python,
and OpenCode runtimes; its size must be measured during packaging.

## Test the Commander panel

1. Confirm the compact, permanently green **commander** pill is visible in the
   global title bar, including on Home with no project session open.
2. Select the global **commander** pill from Home, an empty draft, and an
   ordinary project. It opens the same independent Commander dialog without
   changing the selected project or requiring a project session. It reserves one
   neutral session in `local/commander-workspace`, not the focused project.
3. Open **Settings → Commander**, choose a visible native OpenCode model, and
   close and reopen Commander. The same selection should remain visible.
4. Send a prompt and confirm streamed Hermes content appears. **Stop** must interrupt
   that same Hermes run. If Hermes cannot authenticate the selected model,
   Commander must show the failure without sending through OpenCode.
5. Switch projects, close and reopen Commander, then relaunch through the same
   command. The Commander conversation identity and model choice should remain unchanged.
6. Make the stored Commander session unavailable, then choose **Reconnect**.
   Commander should recreate the reserved session using the configured workspace
   and agent.

This tests the patched Commander panel and Hermes run path. Panel reservation
does not send a provider request; the optional **Send** step does.

## Scheduling status

The basic Commander panel does not start Kirei when launched directly. The
Overmind command above starts it alongside the panel. The trusted OpenCode plugin
issues the one-use capability itself, so no capability token is exposed to the
model. Due-task delivery still needs the local OpenCode service authorization
value for Kirei. It remains outside Git; the panel reservation supplies the
selected Commander session identity.

All generated checkout, workspace, env, dependency, and temporary files from
this guide stay under ignored `local/` paths in this repository.

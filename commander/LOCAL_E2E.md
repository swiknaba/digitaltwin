# Commander local guide

Run this from the root of your existing DigitalTwin checkout. It prepares the
patched OpenCode source under this checkout's ignored `local/` directory; it
does not clone DigitalTwin or use a sibling checkout.

## Prerequisites

- macOS, Git, Bun `1.4.2`, and the OpenCode desktop build prerequisites.
- Your normal OpenCode provider/model configuration, with an agent named
  `commander`. Keep provider credentials in that existing OpenCode setup, not
  in this repository or its Commander env file.

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

Create the non-secret operator environment file once, without overwriting an
existing one:

```sh
if [ ! -f "$REPO_ROOT/local/commander.env" ]; then
  cp "$REPO_ROOT/local/opencode/commander.env.example" "$REPO_ROOT/local/commander.env"
fi
${EDITOR:-vi} "$REPO_ROOT/local/commander.env"
```

Set these values in `local/commander.env`:

```sh
DIGITALTWIN_COMMANDER_WORKSPACE=/absolute/path/to/digitaltwin/local/commander-workspace
DIGITALTWIN_COMMANDER_AGENT=commander
```

Use the absolute path formed by `"$REPO_ROOT/local/commander-workspace"` for
the first value. The launcher validates that workspace and agent, uses
`local/tmp` for its subprocesses, and keeps credentials out of this file.

Start the full local stack from the DigitalTwin repository root:

```sh
sh scripts/local-overmind
```

This starts one patched OpenCode desktop (including its local sidecar), Kirei
web, and the Kirei worker. It uses the checked-in non-secret `.env.overmind`
and the existing host PostgreSQL on `127.0.0.1:5432`; it creates only the
dedicated `digitaltwin_local` and `digitaltwin_local_test` databases when they
do not exist.

## Test the Commander panel

1. Open an ordinary project session in OpenCode.
2. Select the clearly labelled **Commander** button in the active session header.
   It should reserve one neutral session
   in `local/commander-workspace`, not the focused project.
3. Send a prompt and confirm streamed content appears. **Stop** must interrupt
   that same session.
4. Switch projects, close and reopen Commander, then relaunch through the same
   command. The Commander conversation identity should remain unchanged.
5. Make the stored Commander session unavailable, then choose **Reconnect**.
   Commander should recreate the reserved session using the configured workspace
   and agent.

This tests the patched Commander panel and normal OpenCode session path. It
does not test a provider account or provision an agent.

## Scheduling status

The basic Commander panel does not start Kirei when launched directly. The
Overmind command above starts it alongside the panel. The trusted OpenCode plugin
issues the one-use capability itself, so no capability token is exposed to the
model. Due-task delivery still needs an operator-selected Commander session and
the local OpenCode service authorization value; those remain outside Git.

All generated checkout, workspace, env, dependency, and temporary files from
this guide stay under ignored `local/` paths in this repository.

# Local Commander and direct-agent activation

This is the only supported activation path in this repository. It is for one
operator-controlled local Docker stack; it is not a Hetzner deployment recipe.
It enables real chat, Hermes Commander (when configured), and project-agent effects
only after a read-only prerequisite check. The normal stack remains gated.

Commander is optional. A verified human can use `@agent` directly in a project
thread with Writer and Reviewer roles. Adding the optional `commander` role lets
the same human ask Hermes to inspect status and route an authorized follow-up;
it does not grant Hermes additional authority or make Commander a required hop.

## What this does and does not validate

`scripts/validate-local-commander` checks the exact mounted role file,
Mattermost identities and memberships, monitored channels, the shared Herdr
socket, the installed Hermes executable, and its versioned server status. It
only performs authenticated reads. It does not start an agent, send a prompt,
perform provider login, consume provider usage, or prove that a provider is
ready. The operator performs those actions explicitly in the final scenario.

The strict `local-dispatch.json` acknowledgement binds activation to the SHA-256
of the mounted role file. Changing role selection, models, launch arguments, or
the acknowledgement makes the next service boot fail closed. `CHAT_VALIDATION_MODE`
alone never enables a runtime effect.

## Prepare ignored local configuration

Start from the default credential-free core and make an ignored directory owned
by the local Docker user:

```sh
cp .env.example .env
mkdir -p .local/commander
chmod 700 .local/commander
```

Create these existing-credential files yourself under `.local/commander`, then
set each to mode `0600`:

```text
listener.token
commander.token
agent.token
roles.json
local-dispatch.json
```

The first three are existing authenticated Mattermost token files. Do not put a
provider key, OAuth token, browser profile, or any secret in Git, `.env`,
`roles.json`, command arguments, or a chat post. Provider state stays in the
Runtime's persistent home and is configured interactively by the operator.

`commander.token` authenticates `@commander`. `agent.token` authenticates
`@agent`.

Create `.local/commander.env` with the absolute path to that directory and the
non-secret Mattermost IDs collected from your authenticated local server:

```sh
MATTERMOST_CHANNEL_IDS=REPLACE_WITH_PROJECT_CHANNEL_ID
MATTERMOST_COMMANDER_BOT_ID=REPLACE_WITH_COMMANDER_BOT_ID
MATTERMOST_AGENT_BOT_ID=REPLACE_WITH_AGENT_BOT_ID
```

For optional Commander routing, also set `COMMANDER_CHANNEL_ID` and include
that same channel in `MATTERMOST_CHANNEL_IDS`. Without both, no Commander
route is enabled and verified humans can still use `@agent` directly.

Keep this file at mode `0600`. It contains no tokens, but remains local so a
channel or bot mapping cannot accidentally be committed.

## Configure the role agents

`roles.json` assigns one agent to each role: Writer, Reviewer, and optionally Commander.
These assignments apply to new sessions. Chat messages cannot currently select another model.

Choose the model in each CLI's settings first. Then record the same selection
in `roles.json`:

| JSON field | Meaning |
| --- | --- |
| `cli` | Executable to start: `codex`, `claude`, or `hermes`. |
| `launch_args` | Arguments passed to that executable. `[]` uses its configured settings. |
| `provider` | Provider of the selected model, such as `openai` or `anthropic`. |
| `model` | Exact selected model name, recorded for audit. This field does not select the model. |
| `family` | Model family, such as `gpt` or `claude`, used to check review independence. |

Writer and Reviewer must have different `provider` and `family` values.
Changing only the model version does not meet this requirement.

### Example: select models through launch arguments

This example starts Codex with GPT-5 and Claude with Sonnet 4.
These are example model IDs; use models available to your accounts.

```json
{
  "writer": {"cli":"codex","provider":"openai","model":"gpt-5","family":"gpt","launch_args":["--model","gpt-5"]},
  "reviewer": {"cli":"claude","provider":"anthropic","model":"claude-sonnet-4-20250514","family":"claude","launch_args":["--model","claude-sonnet-4-20250514"]}
}
```

The Writer's `launch_args` select `gpt-5`. Its `model` field records `gpt-5`.
Both values must match. The Reviewer follows the same rule.

The effective CLI selections are:

```sh
codex --model gpt-5
claude --model claude-sonnet-4-20250514
```

These lines explain the selections; the backend starts the agents through Herdr.
See the [Claude CLI reference](https://docs.anthropic.com/en/docs/claude-code/cli-usage) for `--model`.

### Example: use the CLI's saved model settings

If Codex already defaults to `gpt-5`, this Writer entry uses that saved setting:

```json
{"cli":"codex","provider":"openai","model":"gpt-5","family":"gpt","launch_args":[]}
```

Changing `model` here to `gpt-5-mini` would only change the recorded label.
To select that model, also change the CLI setting or supply matching launch arguments.

### Example: add Commander

If your private Hermes profile selects OpenAI's `gpt-5`, add this entry alongside Writer and Reviewer:

```json
"commander": {"cli":"hermes","provider":"openai","model":"gpt-5","family":"gpt","launch_args":[]}
```

Use Hermes's [model configuration](https://hermes-agent.nousresearch.com/docs/user-guide/configuring-models) to select its actual provider and model.
Commander may use the same model as Writer; the diversity rule compares only Writer and Reviewer.

### Examples: independent review

| Writer | Reviewer | Allowed? |
| --- | --- | --- |
| OpenAI GPT-5 (`openai`, `gpt`) | Anthropic Sonnet 4 (`anthropic`, `claude`) | Yes: both provider and family differ. |
| OpenAI GPT-5 (`openai`, `gpt`) | OpenAI GPT-5 mini (`openai`, `gpt`) | No: same provider and family. |
| Anthropic Sonnet (`anthropic`, `claude`) | Anthropic Opus (`anthropic`, `claude`) | No: same provider and family. |

The backend records your declared model identity; it does not verify the CLI's
actual model. Keep the CLI settings and this file consistent.

Only after reviewing that role selection, create the local acknowledgement. It
is not a credential and it does not contact a provider:

```sh
role_hash=$(shasum -a 256 .local/commander/roles.json | awk '{print $1}'); printf '{"schema":"digitaltwin.local-dispatch/v1","scope":"local","confirmed_at":"%s","role_config_sha256":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$role_hash" > .local/commander/local-dispatch.json
chmod 600 .local/commander/local-dispatch.json
```

## Verify prerequisites before enabling workers

Load the local mapping, build the reviewed images, and start only the services
needed for the read-only preflight. The `chat-validation` profile is a Compose
grouping name here; this overlay sets `CHAT_VALIDATION_MODE=0` and relies on the
file-gated local activation instead.

```sh
./scripts/dev --build

docker compose --env-file .env --env-file .local/commander.env -f compose.yml -f compose.local-commander.yml up -d --wait mattermost agent-runtime backend-migrate backend-web
scripts/validate-local-commander
```

The command must print JSON with `provider_call:false` and `runtime_effect:false`,
then Herdr's compatible status. If it fails, keep dispatch disabled and fix the
reported token, membership, channel, role, socket, or Hermes-installation issue.
Do not edit the acknowledgement merely to bypass a failed check.

The worker and listener repeat these same read-only identity, membership, and
Herdr checks when local activation is present. Running them directly therefore
still fails closed if the configured server, channels, bots, or socket no
longer match the acknowledged local setup.

## Map one local project before the first worker request

The first release operates on an explicitly mapped project channel. Before
enrolling it, put an already authorized Git checkout at
`/workspace/repos/<owner>/<repository>` in the shared Runtime workspace. It
must be a repository root whose `origin` matches the requested GitHub slug;
the repository is never copied into the backend image. A public clone can be
made by the operator from the Runtime shell, for example:

```sh
docker compose --env-file .env --env-file .local/commander.env -f compose.yml -f compose.local-commander.yml exec -T agent-runtime sh -lc 'mkdir -p /workspace/repos/OWNER && git clone -- https://github.com/OWNER/REPOSITORY.git /workspace/repos/OWNER/REPOSITORY'
```

For a private repository, use your already authorized Git setup instead; do
not add a Git credential to this repository, the local overlay, or chat.

Then run the explicit, one-project registration command. Replace the values
with the mapped Mattermost project channel, a verified non-bot human user ID
from that channel, and the matching repository slug:

```sh
docker compose --env-file .env --env-file .local/commander.env -f compose.yml -f compose.local-commander.yml run --rm --no-deps backend-worker bin/enroll-local-project --channel-id REPLACE_WITH_PROJECT_CHANNEL_ID --human-id REPLACE_WITH_HUMAN_USER_ID --slug OWNER/REPOSITORY
```

This command re-runs the local read-only preflight, verifies the supplied human
and membership through Mattermost, and only registers an existing checkout. It
does not clone/create a repository, post to chat, start a session, or contact a
provider. A second identical command reports a retained mapping; a different
slug for the same channel fails closed.

After that preflight succeeds, start the two effect-owning services:

```sh
docker compose --env-file .env --env-file .local/commander.env -f compose.yml -f compose.local-commander.yml --profile chat-validation up -d --wait backend-worker backend-chat-listener
```

## Human-run live acceptance

These final actions are deliberately manual because they use the operator's own
provider configuration and may consume paid provider usage. First complete the
provider's normal Hermes and worker-CLI setup in the Runtime; do not automate a
login through this repository or chat.

1. From that verified human account in the mapped project channel, create a new
   root thread with `@agent start` and a bounded test task. This proves the
   direct human-to-worker path and retains the normal review/approval gates.
2. If Hermes is configured, post `@commander` in the configured Commander channel
   asking for the status of that exact task, then send one bounded follow-up to
   the same task. Confirm that Hermes reports only backend-verified status and
   the Writer receives the follow-up in its existing conversation.
3. Restart only `backend-web`, `backend-worker`, and `backend-chat-listener`.
   Post one more follow-up. Confirm it returns to the original source thread,
   uses the same recorded session, and does not duplicate the prior reply.
4. Ask for status again. Treat queued, active, delivered, and uncertain results
   as distinct. If any runtime effect is uncertain, use the exact documented
   human recovery command; never restart a command or edit database state to
   obtain a green result.

Record sanitized IDs, revisions, state transitions, and the observed Hermes and
worker session identities outside Git. This proves a local acceptance scenario,
not a production or Hetzner acceptance. A remote deployment needs a separate
approved infrastructure and evidence design.

## Disable

Stop the listener and worker, remove the local acknowledgement file, then start
again without `compose.local-commander.yml`. Existing records remain durable;
new runtime effects stay gated. Do not use this local overlay on Hetzner.

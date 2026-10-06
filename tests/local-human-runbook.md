# Local human test runbook

Use this runbook for one disposable local Docker stack. It does not configure
production, Hetzner, provider accounts, or Git credentials.

The local Mattermost configuration enables bot creation and personal access
tokens. This is intentional for local testing. Do not use this configuration
as a production security baseline.

## What you need

Create one private project channel and add these three local accounts:

| Identity | Mattermost username | Purpose | Local token file |
| --- | --- | --- | --- |
| Human | `root` | Starts and steers the test workflow. | None |
| Listener | The same `root` account for this test | Reads posts and verifies identities. | `listener.token` |
| Commander bot | `commander` | Posts Commander replies. | `commander.token` |
| Agent bot | `agent` | Posts Writer and Reviewer workflow replies. | `agent.token` |

The listener can use the human account during this local test. A separate
non-bot listener account is optional later.

A token file contains only one Mattermost personal access token. Do not add
`Bearer `, JSON, labels, or an account ID. Mattermost displays each token once.

## 1. Start Mattermost

```sh
./scripts/dev
docker compose ps
```

`compose.yml` fixes the local project name as `digitaltwin`. Plain
`docker compose up`, `ps`, and `down` therefore target the same stack.

Open [http://localhost:8065](http://localhost:8065). Create the first account
with username `root`; it becomes the local system administrator.

## 2. Create the channel and identities

1. Create or select one local team.
2. Create one private project channel.
3. Add `root` to that channel.
4. Open **Product menu → Integrations → Bot Accounts → Add Bot Account**.
5. Create the Commander bot with these values:

   | Field | Value |
   | --- | --- |
   | Username | `commander` |
   | Display Name | `Commander` |
   | Description | `Local Commander status and follow-up bot` |
   | Role | `Member` |
   | Bot Icon | Default icon |
   | `post:all` | Unchecked |
   | `post:channels` | Unchecked |

6. Select **Create Bot Account** and copy its token before selecting **Done**.
7. Repeat for the Agent bot. Change only these values:

   | Field | Value |
   | --- | --- |
   | Username | `agent` |
   | Display Name | `Agent` |
   | Description | `Local project workflow agent` |

8. Add both bots to the local team and the project channel.
9. As `root`, open **Profile → Security → Personal Access Tokens**. Create and
   copy one listener token.

Keep `post:all` and `post:channels` unchecked. Channel membership grants the
bots the access that this stack needs. Do not grant either bot System Admin.

## 3. Save the three tokens

All files below are general local-stack configuration. They are not fixtures
for one test run. Reuse them until you reset the local Mattermost data or
revoke a token.

```sh
mkdir -p .local/commander
chmod 700 .local/commander
```

Create these ignored files under `.local/commander/` with an editor or password
manager. Do not paste a token into a shell command, issue, chat, or Git file.

```text
listener.token     token for the local human listener account
commander.token    token for the @commander bot
agent.token        token for the @agent bot
```

Then lock them:

```sh
chmod 600 .local/commander/{listener,commander,agent}.token
```

## 4. Collect IDs and write the local mapping

Get the project channel, `root` user, Commander bot, and Agent bot IDs. The
listener token belongs to `root` in this runbook. Replace uppercase placeholders
before running a command.

```sh
docker compose exec -T mattermost /mattermost/bin/mmctl user search root --json --local
docker compose exec -T mattermost /mattermost/bin/mmctl bot list --all --json --local
docker compose exec -T mattermost /mattermost/bin/mmctl channel search --team YOUR_TEAM_NAME YOUR_CHANNEL_NAME --json --local
```

Create `.local/commander.env` and replace each placeholder:

```sh
MATTERMOST_CHANNEL_IDS=REPLACE_WITH_PROJECT_CHANNEL_ID
MATTERMOST_COMMANDER_BOT_ID=REPLACE_WITH_COMMANDER_BOT_ID
MATTERMOST_AGENT_BOT_ID=REPLACE_WITH_AGENT_BOT_ID
```

```sh
chmod 600 .local/commander.env
```

`MATTERMOST_COMMANDER_*` always describes `@commander`.
`MATTERMOST_AGENT_*` always describes `@agent`.

If `roles.json` includes a Commander role, also set
`COMMANDER_CHANNEL_ID`. Use the project channel ID, or add a separate channel
to `MATTERMOST_CHANNEL_IDS`. Add both bots to every monitored channel.

## 5. Add roles and validate the chat setup

Create `.local/commander/roles.json` using the [role setup reference](../docs/interfaces/local-commander-activation.md#configure-the-role-agents).

For example, this setup selects GPT-5 for Writer and Sonnet 4 for Reviewer:

```json
{
  "writer": {"cli":"codex","provider":"openai","model":"gpt-5","family":"gpt","launch_args":["--model","gpt-5"]},
  "reviewer": {"cli":"claude","provider":"anthropic","model":"claude-sonnet-4-20250514","family":"claude","launch_args":["--model","claude-sonnet-4-20250514"]}
}
```

Use model IDs available to your accounts. `launch_args` selects the actual
model; `model` records its name. Keep those values identical.
Chat messages cannot currently change this selection.

Writer and Reviewer must use different providers and model families. The JSON
key `family` means model family, such as `gpt` or `claude`.
GPT-5 and GPT-5 mini both belong to `gpt`; they cannot form this review pair.

For Commander and saved CLI defaults, use the examples in the role setup reference.

Create the acknowledgement after reviewing the role file:

```sh
role_hash=$(shasum -a 256 .local/commander/roles.json | awk '{print $1}'); printf '{"schema":"digitaltwin.local-dispatch/v1","scope":"local","confirmed_at":"%s","role_config_sha256":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$role_hash" > .local/commander/local-dispatch.json
chmod 600 .local/commander/{roles.json,local-dispatch.json}
```

Start the read-only validation services:

```sh
set -a
. .local/commander.env
set +a

./scripts/dev --build

docker compose --env-file .env --env-file .local/commander.env -f compose.yml -f compose.local-commander.yml up -d --wait mattermost agent-runtime backend-migrate backend-web
scripts/validate-local-commander
```

The validation checks tokens, bot identities, membership, roles, and Herdr.
It does not contact a provider or start a workflow.

## 6. Enroll one project and run the test

Configure provider access manually in the Runtime container. Do not save a
provider credential in this repository, `.env`, a role file, or chat.

Place the target checkout at `/workspace/repos/OWNER/REPOSITORY`, then enroll
the channel and human:

```sh
docker compose --env-file .env --env-file .local/commander.env -f compose.yml -f compose.local-commander.yml run --rm --no-deps backend-worker bin/enroll-local-project --channel-id REPLACE_WITH_PROJECT_CHANNEL_ID --human-id REPLACE_WITH_HUMAN_USER_ID --slug OWNER/REPOSITORY
```

Start effects:

```sh
docker compose --env-file .env --env-file .local/commander.env -f compose.yml -f compose.local-commander.yml --profile chat-validation up -d --wait backend-worker backend-chat-listener
```

As the enrolled human, create a new root post in the project channel:

```text
@agent start
<one small, bounded task>
```

Watch the same thread for the receipt and reply. If configured, use
`@commander` in the Commander channel only for status and follow-up.

## Stop safely

Stop effects but retain local data:

```sh
docker compose --env-file .env --env-file .local/commander.env -f compose.yml -f compose.local-commander.yml --profile chat-validation stop backend-worker backend-chat-listener
rm .local/commander/local-dispatch.json
```

Stop the stack but retain local data:

```sh
docker compose --env-file .env --env-file .local/commander.env -f compose.yml -f compose.local-commander.yml --profile chat-validation down
```

Do not use `down --volumes` unless you intend to erase the local Mattermost
accounts, tokens, and project data.

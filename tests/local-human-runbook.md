# Local human test runbook

Use this runbook for one disposable local Docker stack. It does not create
production, Hetzner, provider, or Git credentials. You configure your own
Runtime Git access before testing work that commits or pushes.

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
```

Create these ignored files under `.local/commander/` with an editor or password
manager. Do not paste a token into a shell command, issue, chat, or Git file.

```text
listener.token     token for the local human listener account
commander.token    token for the @commander bot
agent.token        token for the @agent bot
```

Then lock them:

## 4. Collect IDs and write the local mapping

Get the project channel, `root` user, Commander bot, and Agent bot IDs. The
listener token belongs to `root` in this runbook. Replace uppercase placeholders
before running a command.

```sh
docker compose exec -T mattermost /mattermost/bin/mmctl user search root --json --local
docker compose exec -T mattermost /mattermost/bin/mmctl bot list --all --json --local
docker compose exec -T mattermost /mattermost/bin/mmctl channel search --team YOUR_TEAM_NAME YOUR_CHANNEL_NAME --json --local
```

Add both bots to the team first, then to the channel. Use the team's URL name
for `YOUR_TEAM_NAME` and the returned channel `id` below.
Direct messages with a bot do not grant team or channel membership.

```sh
docker compose exec -T mattermost /mattermost/bin/mmctl team users add YOUR_TEAM_NAME commander agent --local
docker compose exec -T mattermost /mattermost/bin/mmctl channel users add REPLACE_WITH_PROJECT_CHANNEL_ID commander agent --local
docker compose exec -T mattermost /mattermost/bin/mmctl channel users list REPLACE_WITH_PROJECT_CHANNEL_ID --json --local
```

The list must include `root`, `commander`, and `agent`.

If channel addition reports “No team member found”, run the team-add command first.

Create `.local/commander.env` and replace each placeholder:

```sh
MATTERMOST_CHANNEL_IDS=REPLACE_WITH_PROJECT_CHANNEL_ID
MATTERMOST_COMMANDER_BOT_ID=REPLACE_WITH_COMMANDER_BOT_ID
MATTERMOST_AGENT_BOT_ID=REPLACE_WITH_AGENT_BOT_ID
```

`MATTERMOST_COMMANDER_*` always describes `@commander`.
`MATTERMOST_AGENT_*` always describes `@agent`.

If `roles.json` includes a Commander role, also set
`COMMANDER_CHANNEL_ID`. Use the project channel ID, or add a separate channel
to `MATTERMOST_CHANNEL_IDS`. Add both bots to every monitored channel.

## 5. Authenticate the available harnesses

Run these commands from the terminal that controls the Docker host. For a
remote server, connect to that host with SSH first. Docker connects the command
to Runtime, where the agents run and their login state is stored.
Use `-it` for login; `-T` disables the interactive terminal.

### Codex

If the browser runs on the same Docker host, publish Runtime's callback and
start the normal Codex login flow:

```sh
docker compose up -d --force-recreate agent-runtime
docker compose exec -it agent-runtime codex login
```

Open the displayed URL in a browser on that Docker host. After sign-in, Codex
redirects to `127.0.0.1:1455`. Compose maps that address to Runtime only on the
Docker host.

For a remote Docker host, use device-code login instead. It does not need a
callback port:

```sh
docker compose exec -it agent-runtime codex login --device-auth
```

Use device-code login only when your ChatGPT workspace enables it. It is
unavailable in some workspaces.

See [Codex authentication](https://developers.openai.com/codex/auth#login-on-headless-devices).

Check the saved login:

```sh
docker compose exec -T agent-runtime codex login status
```

### Claude Code

```sh
docker compose exec -it agent-runtime claude auth login --claudeai
```

Open the displayed URL in your Mac browser and sign in with your Claude account.
If the browser displays a login code, paste it into the waiting terminal.
See [Claude authentication](https://code.claude.com/docs/en/authentication).

Check the saved login:

```sh
docker compose exec -T agent-runtime claude auth status --text
```

This confirms that Runtime has saved Claude credentials. It does not send a
model request. Start `claude` to confirm an interactive session.

If a Claude pane in Herdr requests login, do not copy its browser URL from the
container UI. Authenticate from the terminal that controls the Docker host:

```sh
docker compose exec -it agent-runtime claude auth login --claudeai
```

After login completes, cancel the old Claude pane with `Ctrl-C`, then run
`claude`. Do not run `claude code`; `code` is only unnecessary prompt text.

### Gemini CLI

Use Gemini's user-code flow. It works from Runtime without publishing a second
browser callback port:

```sh
docker compose exec -it -e NO_BROWSER=true agent-runtime gemini
```

Select **Log in with Google**. Open the displayed URL, sign in, then paste the
displayed authorization code into the waiting terminal. Exit Gemini after it
confirms authentication.

Google Workspace accounts can require a Google Cloud project. Follow Gemini's
[authentication guide](https://google-gemini.github.io/gemini-cli/docs/get-started/authentication.html)
if it requests one.

### Grok Build

Use Grok's device-code flow:

```sh
docker compose exec -it agent-runtime grok login --device-auth
```

Open the displayed URL, sign in to xAI, and enter the displayed code.
See the [Grok Build CLI reference](https://docs.x.ai/build/cli/reference).

### Hermes Commander

Hermes is its own harness. Codex, Gemini, and Grok CLI logins make those
harnesses available to Herdr. They do not select or authenticate Hermes's
inference provider.

Configure Hermes separately before using Commander:

```sh
docker compose exec -it agent-runtime hermes model
```

Choose the provider and model in the Hermes picker. Complete any provider login
that Hermes requests.

`Google AI Studio` is Hermes's Gemini provider. It uses a Gemini API key; it
does not reuse Gemini CLI's Google-account login. Hermes's `xAI Grok` provider
is also separate from Grok Build login. Its picker offers either xAI API
credentials or an eligible xAI subscription OAuth flow.

Hermes uses one selected primary provider and model. Configuring other providers
does not make Hermes rotate among them. A configured fallback runs only after
the primary provider fails.

`Mixture of Agents` is an explicit Hermes preset. It calls the preset's named
reference models, then an aggregator model. It does not automatically use every
installed or logged-in harness. Configure each referenced provider first. Expect
one request per reference model plus the aggregator.

All saved login state persists in Runtime's `runtime-home` Docker volume across
normal stops and restarts. Logging in on your Mac alone does not authenticate
Runtime. Status checks do not run a model prompt.

### Open the Herdr terminal interface

To view Herdr's multiplexed terminals from your Mac terminal, run:

```sh
docker compose exec -it agent-runtime herdr
```

This attaches to the running Herdr server inside Runtime. It needs no additional
Herdr installation. Use it from your SSH terminal when Docker runs remotely.
Agents started through Herdr use the matching saved harness login.

To return to your Mac terminal, press `Ctrl-B`, release it, then press `Q`.
This detaches the client. It does not stop Herdr or any running agent.

## 6. Add roles and validate the chat setup

Create `.local/commander/roles.json` using the [role setup reference](../docs/interfaces/local-commander-activation.md#configure-the-role-agents).

For this temporary local test, use Codex as Writer and Claude as Reviewer
with their configured model defaults:

```json
{
  "writer": {"cli":"codex","provider":"openai","model":"cli-default","family":"gpt","launch_args":[]},
  "reviewer": {"cli":"claude","provider":"anthropic","model":"cli-default","family":"claude","launch_args":[]}
}
```

`cli-default` is a temporary audit label required by the current parser.
It is not passed to the CLI. Empty `launch_args` uses the CLI's saved settings.

Writer and Reviewer must use different providers and model families. The JSON
key `family` means model family, such as `gpt` or `claude`.
GPT-5 and GPT-5 mini both belong to `gpt`; they cannot form this review pair.

For Commander and saved CLI defaults, use the examples in the role setup reference.

Create the acknowledgement after reviewing the role file:

```sh
role_hash=$(shasum -a 256 .local/commander/roles.json | awk '{print $1}'); printf '{"schema":"digitaltwin.local-dispatch/v1","scope":"local","confirmed_at":"%s","role_config_sha256":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$role_hash" > .local/commander/local-dispatch.json
```

Start the read-only validation services:

```sh
./scripts/dev --build

docker compose --env-file .env --env-file .local/commander.env -f compose.yml -f compose.local-commander.yml up -d --wait mattermost agent-runtime backend-migrate backend-web
scripts/validate-local-commander
```

The validation checks tokens, bot identities, membership, roles, and Herdr.
It does not contact a provider or start a workflow.

## 7. Add a repository, enroll it, and run the test

This stack starts with an empty Runtime workspace. Do these steps in order:

1. Clone the repository into Runtime.
2. Enroll the checkout to the Mattermost project channel.
3. Start the chat services.

**Enrollment does not clone a repository.** It stores one mapping:
Mattermost project channel + human identity -> existing Runtime checkout.
It does not create Git credentials, make commits, push, or contact a provider.

### Configure Runtime Git access

Do this once for each Runtime volume. It is required for an agent to commit and
push. Use a repository you own for the write test. A public repository that you
do not own permits cloning, but cannot accept your push.

Use a dedicated GitHub deploy key when testing one repository. It has access to
that repository only. Run these commands from a regular Runtime shell:

```sh
docker compose exec -it agent-runtime bash
mkdir -p ~/.ssh
ssh-keygen -t ed25519 -C digitaltwin-runtime -f ~/.ssh/id_ed25519
cat ~/.ssh/id_ed25519.pub
```

At the passphrase prompt, press Enter. Herdr cannot enter a passphrase for an
unattended agent. Copy only the displayed public key. Do not copy the private
key into GitHub, Mattermost, Git, or any local configuration file.

In the GitHub repository, open **Settings** > **Deploy keys** > **Add deploy
key**. Paste the public key, then select **Allow write access** for this test.
Return to the Runtime shell and set the Git author identity used for commits:

```sh
git config --global user.name "YOUR_GIT_AUTHOR_NAME"
git config --global user.email "YOUR_GIT_AUTHOR_EMAIL"
ssh -T git@github.com
exit
```

Confirm GitHub recognizes the key. GitHub's successful SSH authentication
message can still return exit status 1; that is normal.

### Clone the test repository into Runtime

Use a regular Runtime shell. Do not use Herdr for setup commands.

Replace the uppercase values below. Do not type angle brackets.

```sh
docker compose exec -it agent-runtime bash
mkdir -p /workspace/repos/YOUR_GITHUB_OWNER
git clone git@github.com:YOUR_GITHUB_OWNER/YOUR_REPOSITORY.git /workspace/repos/YOUR_GITHUB_OWNER/YOUR_REPOSITORY
git -C /workspace/repos/YOUR_GITHUB_OWNER/YOUR_REPOSITORY status --short
exit
```

For a clone-only test, HTTPS works without Git credentials. Do not use a
repository you cannot write to when testing agent commits or pushes.

### Enroll that checkout to the project channel

Enrollment is a one-time command. It is not a Mattermost message, button, or
configuration-file edit. The command below records this mapping in
Digitaltwin's database:

```text
Mattermost project channel + root human account -> Runtime Git checkout
```

Get the Mattermost user ID for the human account. `root` is the default human
username in this runbook. Copy the value of its JSON `id` field.

```sh
docker compose exec -T mattermost /mattermost/bin/mmctl user search root --json --local
```

Run the enrollment command from the Docker host's shell, not from a Runtime or
Herdr shell. Replace the uppercase values. `YOUR_PROJECT_CHANNEL_ID` is the channel ID you saved in
`.local/commander.env`. `YOUR_ROOT_USER_ID` is the JSON `id` from the command
above. `YOUR_GITHUB_OWNER/YOUR_REPOSITORY` must exactly match the directory
you cloned in the preceding step.

```sh
docker compose --env-file .env --env-file .local/commander.env -f compose.yml -f compose.local-commander.yml run --rm --no-deps backend-worker bin/enroll-local-project --channel-id YOUR_PROJECT_CHANNEL_ID --human-id YOUR_ROOT_USER_ID --slug YOUR_GITHUB_OWNER/YOUR_REPOSITORY
```

Expected output contains `"enrollment":"enrolled"`. Re-running the same
command returns `"enrollment":"retained"`.

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

# Human local activation runbook

Use this for one operator-owned **local Docker** stack. It is not a production
or Hetzner deployment guide. The normal stack is credential-free; live worker
and optional Commander effects require the explicit local activation below.

For rationale, field definitions, and recovery rules, see the detailed
[local activation reference](../docs/interfaces/local-commander-activation.md).

## 1. Start the safe local core

Prerequisite: Docker Desktop (or a compatible local Docker daemon) is running.

```sh
project=digitaltwin-local-commander
COMPOSE_PROJECT_NAME="$project" ./scripts/dev
docker compose -p "$project" ps
curl -fsS http://localhost:3000/readyz
```

Open [http://localhost:8065](http://localhost:8065) to use the local Mattermost
UI. `docker compose ps` should show the core services healthy; `/readyz` only
shows backend health. Neither proves provider, listener, or Commander access.

To stop the core without deleting its local data:

```sh
docker compose -p "$project" down
```

Do not add `--volumes` unless you intentionally want to erase this local stack.

## 2. Prepare the human-owned chat and role setup

In the Mattermost UI, create or select the local project channel and the human
and bot identities you will use. Obtain their existing authenticated token files
through your normal Mattermost operator process; this repository does not create
or print tokens.

```sh
mkdir -p .local/commander
chmod 700 .local/commander
```

Place these local-only files in `.local/commander/`:

```text
listener.token     authenticated listener token
agent.token        authenticated agent-bot token
worker.token       authenticated worker-bot token
roles.json         Writer/Reviewer roles; optional Commander role
```

After you create those files with your existing values, lock their modes:

```sh
chmod 600 .local/commander/{listener,agent,worker}.token .local/commander/roles.json
```

Create `.local/commander.env` with your own IDs. Keep it local and mode 0600:

```sh
cat > .local/commander.env <<'EOF'
DIGITALTWIN_LOCAL_CONFIG_DIR=/absolute/path/to/digitaltwin/.local/commander
MATTERMOST_CHANNEL_IDS=<project-channel-id>
MATTERMOST_LOCAL_BOT_IDS=<agent-bot-id>,<worker-bot-id>
MATTERMOST_AGENT_BOT_ID=<agent-bot-id>
MATTERMOST_WORKER_BOT_ID=<worker-bot-id>
MATTERMOST_PEER_BOT_IDS=
# Optional: set this only when roles.json contains a commander role.
# COMMANDER_CHANNEL_ID=<commander-channel-id>
EOF
chmod 600 .local/commander.env
```

`roles.json` must contain different Writer and Reviewer `provider` and `family`
values. Add the optional Commander entry only when it uses `"cli":"hermes"`.
Provider/model names describe a role; they are not credentials. Use the exact
shape in the [detailed reference](../docs/interfaces/local-commander-activation.md#prepare-ignored-local-configuration).

After you review the roles, create the acknowledgement that binds activation to
this exact file:

```sh
role_hash=$(shasum -a 256 .local/commander/roles.json | awk '{print $1}')
printf '{"schema":"digitaltwin.local-dispatch/v1","scope":"local","confirmed_at":"%s","role_config_sha256":"%s"}\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$role_hash" > .local/commander/local-dispatch.json
chmod 600 .local/commander/local-dispatch.json
```

Changing `roles.json` invalidates this acknowledgement. Regenerate it only
after reviewing the new role selection; do not edit it to bypass a failed check.

## 3. Start and validate activation — no provider call

```sh
set -a
. .local/commander.env
set +a

docker compose --env-file .env --env-file .local/commander.env -p "$project" \
  -f compose.yml -f compose.local-commander.yml up --build -d --wait \
  mattermost agent-runtime backend-migrate backend-web

scripts/validate-local-commander "$project"
```

Expected terminal output includes JSON with
`"local_dispatch_activation":true`, `"provider_call":false`, and
`"runtime_effect":false`, followed by a compatible `herdr status` JSON.
If it fails, leave worker/listener stopped and fix the reported token, bot,
channel, role, acknowledgement, Hermes, or socket problem.

## 4. Configure provider access manually, then map one project

Provider login is a human action and may incur usage. In a Runtime shell, use
the provider's normal Hermes and worker-CLI configuration flow; do not put a
provider key, OAuth token, browser profile, or login command in this repository,
`.env`, role file, or chat message.

```sh
docker compose --env-file .env --env-file .local/commander.env -p "$project" \
  -f compose.yml -f compose.local-commander.yml exec -it agent-runtime sh
```

Exit that shell after your provider's normal setup. This runbook does not start
or prompt a provider for you.

Before the first worker request, place the intended checkout in the Runtime
workspace. For a public repository, an operator can use:

```sh
docker compose --env-file .env --env-file .local/commander.env -p "$project" \
  -f compose.yml -f compose.local-commander.yml exec -T agent-runtime \
  sh -lc 'mkdir -p /workspace/repos/OWNER && git clone -- https://github.com/OWNER/REPOSITORY.git /workspace/repos/OWNER/REPOSITORY'
```

For a private repository, use your already authorized Git setup; do not add a
Git credential to this repository or to chat. Then register the project channel
and verified human. This is an authenticated read/registration, not a provider
call or agent start:

```sh
docker compose --env-file .env --env-file .local/commander.env -p "$project" \
  -f compose.yml -f compose.local-commander.yml run --rm --no-deps backend-worker \
  bin/enroll-local-project --channel-id <project-channel-id> \
  --human-id <human-user-id> --slug OWNER/REPOSITORY
```

Expected output includes `"enrollment":"..."`, `"provider_call":false`, and
`"runtime_effect":false`.

## 5. Start effects and perform the human test

```sh
docker compose --env-file .env --env-file .local/commander.env -p "$project" \
  -f compose.yml -f compose.local-commander.yml --profile chat-validation up -d --wait \
  backend-worker backend-chat-listener

docker compose --env-file .env --env-file .local/commander.env -p "$project" \
  -f compose.yml -f compose.local-commander.yml ps
```

Where to act and check:

- In Mattermost, use the mapped **project channel** as the verified human.
  Start a new root thread with `@worker start` and one small, bounded test task.
  Watch the same thread for its receipt/reply.
- For optional Commander, use the configured **Commander channel**. Post
  `@agent` asking for the status of that exact task, then send one bounded
  follow-up to the same task. Confirm it refers to the existing task rather
  than creating a replacement.
- In a terminal, inspect only the relevant local services:

  ```sh
  docker compose --env-file .env --env-file .local/commander.env -p "$project" \
    -f compose.yml -f compose.local-commander.yml logs -f --tail=100 \
    backend-worker backend-chat-listener agent-runtime
  ```

Success for this manual acceptance means a response appears in the original
Mattermost thread and the follow-up stays on the same recorded task/session.
Do not treat a container health check as provider success.

## 6. Restart and memory check

Restart only the application services, then post one more follow-up in the same
Mattermost thread:

```sh
docker compose --env-file .env --env-file .local/commander.env -p "$project" \
  -f compose.yml -f compose.local-commander.yml --profile chat-validation restart \
  backend-web backend-worker backend-chat-listener
```

Expected result: the follow-up returns to the original source thread, reuses
the recorded session, and does not duplicate an earlier reply. Treat `queued`,
`active`, `delivered`, and `uncertain` as different outcomes. If an effect is
uncertain, do **not** repost or restart it; use the exact human recovery command
in the [detailed reference](../docs/interfaces/commander-routing-setup.md#feature-boundary).

## Troubleshooting and safe stop

- **Preflight or enrollment fails:** keep effects stopped; fix the named local
  file, membership, channel/bot ID, workspace checkout, or Hermes/socket issue,
  then rerun the same preflight.
- **Service is not healthy:** run the `ps` and `logs` commands above. Do not
  paste token values or private chat content into an issue or chat.
- **Stop effects but retain data:**

  ```sh
  docker compose --env-file .env --env-file .local/commander.env -p "$project" \
    -f compose.yml -f compose.local-commander.yml --profile chat-validation stop \
    backend-worker backend-chat-listener
  rm .local/commander/local-dispatch.json
  ```

- **Stop the whole local stack but retain data:**

  ```sh
  docker compose --env-file .env --env-file .local/commander.env -p "$project" \
    -f compose.yml -f compose.local-commander.yml --profile chat-validation down
  ```

Never use `down --volumes` unless you intentionally want to remove local data.

## Command verification

The commands above are derived from the checked-in Compose files,
`scripts/dev`, `scripts/validate-local-commander`, and the two backend commands.
They are configuration-checked without credentials. Provider login, real chat
identities, project enrollment, and any live provider prompt are deliberately
not executed by this guide or its automated tests.

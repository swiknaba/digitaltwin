# Integration Backend

The routing layer between chat (Mattermost) and the LLM agent sessions that run on the server.

## Why this exists

Agent sessions run on a server. People talk to them in chat. Something must sit between the two.
It decides which message goes to which session, who may steer it, and which thread receives the result.
Without it, any chat member could prompt any agent, a reconnect could deliver a message twice,
and a lost reply could go to the wrong thread. This service verifies the sender,
routes the message, and posts the agent's result back to the thread it came from.

## What it does

- Verifies each human message (channel, thread, sender), then routes it to the Master or to a workflow session.
- Moves a workflow through spec, plan, implementation, review, and human approval gates.
  Approvals name an exact commit. A changed artifact fails closed.
- Lets agent sessions post results, artifacts, and review requests back to their thread.
- Delivers each message once. An external effect with an unknown outcome is marked `uncertain`
  and held for a human to reconcile with a `recover-*` command. It is never retried blindly.

## Chat commands

Handles default to `@agent` and `@worker` (`AGENT_HANDLE`, `WORKER_HANDLE`). Each command is the whole message.

| Command | Effect |
| --- | --- |
| `@agent approve WORKFLOW_ID spec\|plan COMMIT_SHA` | Approve a workflow gate at an exact 40-character commit. |
| `@agent route WORKFLOW_ID` + newline + text | Send the text to that workflow's Writer session. |
| `@agent recover-master REQUEST_ID` | Close an expired or uncertain Master request. No prompt replay. |
| `@agent recover-start REQUEST_ID THREAD_ID` | Continue a thread start against the existing root post. |
| `@agent recover-session OPERATION_ID PANE_ID` | Resolve an uncertain session start or stop. |
| `@agent recover-followup FOLLOWUP_ID delivered\|discard` | Record the human outcome of a lost follow-up. |
| `@worker start` (new thread root) | Start a workflow for the channel's enrolled project in this thread. |
| `@worker approve` | Approve the artifact waiting at the current human-approval gate. |
| `@worker pause` / `resume` | Pause the workflow; resume only if the revision did not change meanwhile. |
| `@worker finish` | Close a delivered workflow and stop its sessions. |
| `@worker cancel` | Cancel the workflow and stop its sessions. |

Only the original human can run a recover command. Details: [Master routing setup](../docs/interfaces/master-routing-setup.md).

## Run it

Roles share one image and one schema. Migrate first. No role migrates at startup, and all refuse to start with pending migrations.

```sh
bundle install
bundle exec rake db:migrate                    # needs DATABASE_URL
bin/web                                        # HTTP: /livez, /readyz, private callbacks
bin/worker                                     # durable jobs and delivery
bin/chat-listener                              # Mattermost ingestion
bin/mcp                                        # stdio bridge for the Master (runs in Runtime, not here)
bin/health web|worker|chat-listener            # container probe
```

Tests need two disposable PostgreSQL databases, `digitaltwin_backend_test` and `digitaltwin_migration_test`:

```sh
DATABASE_URL=... MIGRATION_TEST_DATABASE_URL=... bin/check   # specs, RuboCop, Sorbet
```

## Configuration

| Variable | Meaning |
| --- | --- |
| `DATABASE_URL` | Dedicated PostgreSQL database and role. Required. Never a Mattermost database. |
| `MATTERMOST_URL` | Private base URL of the Mattermost server. |
| `MATTERMOST_LISTENER_TOKEN_FILE` | File with the listener credential. |
| `MATTERMOST_WORKER_TOKEN_FILE`, `MATTERMOST_AGENT_TOKEN_FILE` | Files with the bot credentials used for delivery. |
| `MATTERMOST_WORKER_BOT_ID`, `MATTERMOST_AGENT_BOT_ID` | Expected bot identities. Checked against the authenticated user. |
| `MATTERMOST_LOCAL_BOT_IDS` | Bots excluded from human authority. Required by the listener. |
| `MATTERMOST_PEER_BOT_IDS` | Other bots to exclude. Optional. |
| `MATTERMOST_CHANNEL_IDS` | Monitored channels. Listed explicitly, never inferred. |
| `MASTER_CHANNEL_ID` | Channel for Master chat. |
| `ROLE_CONFIG_FILE` | Trusted Controller, Writer, and Reviewer profiles (CLI, provider, model). |
| `AGENT_HANDLE`, `WORKER_HANDLE` | Chat handles. Default `agent`, `worker`. |
| `WORKSPACE_ROOT`, `WORKTREE_ROOT` | Shared repo and worktree mounts. Default `/workspace/repos`, `/workspace/worktrees`. |
| `PORT`, `WEB_PROCESSES` | Web port and process count. Default `3000`, `1`. |
| `DB_POOL_SIZE`, `DB_POOL_TIMEOUT` | Connection pool size and wait seconds. Default `5`, `2`. |
| `HEARTBEAT_DIR` | Where worker and listener write heartbeats. Default `/tmp`. Stale after 60 seconds. |
| `CHAT_VALIDATION_MODE` | `1` opens the listener and delivery for disposable chat checks only. |
| `DIGITALTWIN_CALLBACK_URL` | Backend URL used by `bin/digitaltwin` and `bin/mcp` in Runtime. |
| `DIGITALTWIN_MASTER_REQUEST_TOKEN_FILE`, `DIGITALTWIN_SESSION_GENERATION` | Per-request Master and per-session credentials for Runtime clients. |

## Operating rules

- Dispatch to agent sessions is blocked. `Policy#dispatch_allowed?` returns `false` until live Herdr,
  authenticated chat, and Master MCP evidence exists. No environment variable overrides it.
  Workflow starts, prompts, reviews, and session renewals stay queued or blocked.
- `CHAT_VALIDATION_MODE=1` does not enable agent sessions, reviews, approvals, or production workflows.
- Store credentials only as mounted read-only files. Keep no tokens, signing keys, or provider login state in Git or images.
- Only the worker mounts Git workspaces and the Herdr socket. Live GitHub creation needs an operator-provided `gh` login.
- The backend never reads or migrates Mattermost tables.
- Callbacks are session-bound and deduplicated. A changed body or a stale generation is rejected.
- Unknown outcomes need human or remote evidence. See the recover commands above.
- Open gates and ownership: [service boundaries](../docs/interfaces/service-boundaries.md).

## Code layout

`app/domains/` holds bounded contexts that own tables and rules. `app/services/` holds cross-domain use cases and job handlers.
`app/adapters/` translates vendors and transports (Mattermost, Herdr, git, credential files, HTTP, MCP).
`app/platform/` holds shared jobs, locks, transactions, audit, and JSON boundary types. Conventions: [AGENTS.md](AGENTS.md).

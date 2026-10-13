# Kirei FutureTasks

Kirei is the durable future-commitment service for Commander. It does not receive
ordinary OpenCode project prompts, transcripts, chat events, reviews, approvals, or
Git workflow control.

## What it owns

- one-time and daily/weekly recurring Commander check-ins with actor-scoped idempotency keys;
- task versions, cancellation, rescheduling, and immutable delivery attempts;
- a durable due-job generation and exactly one delivery key per generation;
- explicit `scheduled`, `running`, `awaiting_disposition`, `completed`, `failed`,
  `canceled`, and `uncertain` task states.

When a task is due, the worker asks the Commander bridge to append a visible check-in.
It never starts project work. A bridge effect with an unknown result becomes
`uncertain`, then one reconciliation attempt uses the same immutable delivery key.
The in-repository gateway fails closed until an operator wires the private bridge
endpoint and identity file; it does not create or ship a credential.

## Capability and bridge contract

`Services::FutureTasks::CapabilityApi` is the single typed API behind the narrow MCP
and global OpenCode tool adapters. Each call consumes one short-lived signed
capability containing only an audience, actor, Commander conversation, expiry, and
nonce. Kirei records the nonce before task mutation, so replayed, expired, or
cross-actor capabilities fail closed. The body never supplies an actor, origin, or
target.

Set all of the following only in operator-owned runtime configuration:

- `COMMANDER_BRIDGE_URL` — private bridge base URL;
- `COMMANDER_BRIDGE_IDENTITY_FILE` — mounted private identity for that bridge; and
- `FUTURE_TASK_CAPABILITY_SECRET_FILE` — mounted verification secret for
  operator-issued capabilities.

Without the bridge values, delivery is explicitly unavailable. Without the capability
secret, the agent scheduling API is unavailable. Neither condition affects ordinary
OpenCode project work.

## Run and verify

```sh
bundle install
bundle exec rake db:migrate  # DATABASE_URL points at an empty Kirei database
bin/web                      # /livez and /readyz only
bin/worker                   # FutureTasks due-job handler
```

For the backend check, use a disposable `digitaltwin_backend_test` PostgreSQL
database:

```sh
DATABASE_URL=... bin/check
```

The greenfield migration is `001_future_tasks.rb`; it intentionally replaces the
historical chat/workflow schema rather than migrating Mattermost data.

## Boundaries

OpenCode owns project sessions, agents, remote workspaces, and Git feedback.
Commander owns its durable conversation and runtime credentials. Kirei receives only
validated future-task operations through the shared MCP/OpenCode tool API. The
production issuer and private bridge deployment remain operator work. No task can trigger a code change,
merge, deployment, or revive a project session by itself.

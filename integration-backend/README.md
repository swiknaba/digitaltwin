# Kirei FutureTasks

Kirei is the durable future-commitment service for Commander. It does not receive
ordinary OpenCode project prompts, transcripts, chat events, reviews, approvals, or
Git workflow control.

## What it owns

- one-time Commander check-ins with actor-scoped idempotency keys;
- task versions, cancellation, rescheduling, and immutable delivery attempts;
- a durable due-job generation and exactly one delivery key per generation;
- explicit `scheduled`, `running`, `awaiting_disposition`, `completed`, `failed`,
  `canceled`, and `uncertain` task states.

There is deliberately no recurrence engine. A due task may create its own next
one-time successor through the same capability API, using a stable successor
idempotency key; a worker retry therefore returns the existing successor instead
of creating a duplicate.

When a task is due, the worker uses the ordinary authenticated OpenCode session API
to append a visible check-in. It never starts project work. An unknown effect becomes
`uncertain`, then one reconciliation attempt uses the same immutable delivery key.
The in-repository gateway fails closed until an operator wires an exact OpenCode
session and authorization file; it does not create or ship a credential.

## Capability and bridge contract

`Services::FutureTasks::CapabilityApi` is the single typed API behind the MCP and
global OpenCode tool adapters. It supports create, cursor-paged list, read, update,
cancel, disposition, and owner resolution. Each call consumes one short-lived signed
capability containing only an audience, actor, Commander conversation, expiry, and
nonce. Kirei records the nonce before task mutation, so replayed, expired, or
cross-actor capabilities fail closed. The body never supplies an actor, origin, or
target; conversation is retained only as creation provenance so a valid Commander
session can manage the actor's Commander-targeted tasks created elsewhere.

The bounded OpenCode host transport is mounted at `/v1/future-tasks` and delegates
only to `Adapters::FutureTasks::OpencodeTool`; it accepts the capability as a Bearer
credential and exposes create/list/read/update/cancel/disposition/resolution routes.
`Services::Composition` constructs both the MCP and OpenCode adapters from the same
capability API, so neither transport can schedule directly or select an actor. This
is an internal task API, not a generic workflow server or a replacement for the
operator-owned native MCP server bootstrap.

Set all of the following only in operator-owned runtime configuration:

- `OPENCODE_URL` — existing authenticated OpenCode server base URL;
- `OPENCODE_SESSION_ID` — exact operator-selected OpenCode session; and
- `OPENCODE_AUTHORIZATION_FILE` — mounted authorization value for that OpenCode server; and
- `FUTURE_TASK_CAPABILITY_SECRET_FILE` — mounted verification secret for
  operator-issued capabilities.

Without the bridge values, delivery is explicitly unavailable. Without the capability
secret, the agent scheduling API is unavailable. Neither condition affects ordinary
OpenCode project work.

The local OpenCode plugin receives the same ignored capability-secret file path
and mints a fresh 60-second capability inside its trusted server process for each
call; it never asks the model to supply or retain a bearer token. Keep the
OpenCode service authorization in its own local file, and configure the bridge
with a Commander session ID only after the panel has reserved that session.

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
validated future-task operations through the shared MCP/OpenCode tool API and
delivers them through an exact operator-selected normal OpenCode session. The
production issuer and OpenCode authorization remain operator work. No task can trigger a code change,
merge, deployment, or revive a project session by itself.

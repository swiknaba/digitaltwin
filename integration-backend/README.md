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

When a task is due, the worker asks the Commander bridge to append a visible check-in.
It never starts project work. A bridge effect with an unknown result becomes
`uncertain`, not a blind retry. The in-repository gateway intentionally fails closed
until an operator-owned Commander runtime is wired; it does not contain credentials
or claim a production bridge.

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
validated future-task operations through the future scheduling capability that is
still being added as MCP/OpenCode tool adapters. No task can trigger a code change,
merge, deployment, or revive a project session by itself.

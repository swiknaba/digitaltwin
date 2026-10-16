# DigitalTwin OpenCode server plugins

These are standard OpenCode v2.0.27 server plugins for the thin desktop client.
They are installed by an operator into an operator-owned global plugin directory;
they do not use project configuration, expose a renderer bridge, or read/write user
configuration. The helper creates symlinks only, so it never stores credentials.

```sh
OPENCODE_GLOBAL_PLUGIN_DIR=/operator-owned/opencode/plugins \
  sh commander/opencode-gate-plugin/install-future-tasks-plugin.sh
```

`future-tasks.ts` registers `future_tasks`. The plugin mints one short-lived,
one-use capability inside the trusted OpenCode server process for each tool call;
the model never receives the token or signing secret. The operator configures all
three values in the same global plugin registration, or through matching
`DIGITALTWIN_FUTURE_TASKS_*` environment variables for the local Overmind workflow:

- `digitaltwinFutureTasksEndpoint` — an HTTPS or loopback
  `/v1/future-tasks` endpoint;
- `digitaltwinFutureTasksCapabilitySecretFile` — an absolute, operator-owned
  file containing the HMAC secret shared with Kirei; and
- `digitaltwinFutureTasksActor` — the stable local actor identifier whose tasks
  this OpenCode installation may manage; and
- `digitaltwinFutureTasksOwner` — an optional boolean, defaulting to `false`.
  Only an explicitly operator-owned installation may set it to `true`, which
  permits the terminal `resolve_uncertain` operation.

The capability binds that actor to the trusted calling OpenCode session as
provenance, is valid for 60 seconds, and is never persisted. Startup rejects a
missing, non-loopback HTTP, non-HTTPS, path-bearing, query-bearing, or
fragment-bearing endpoint value.

`commander-continuation.ts` is the normal server-plugin composition for
Commander. It binds a decision from the trusted completion result of OpenCode's
native `subagent` tool, recording both the Commander parent and its actual child
session in plugin storage. Its
`commander_continue_agent` tool looks up that immutable decision and calls
`context.session.prompt` for that exact session with a deterministic message id
and `fromCommander` plus body-digest metadata. Neither tool accepts a session,
message, project, endpoint, or credential from the caller.

The isolated fixture is validation-only: set `XDG_CONFIG_HOME` to
`commander/opencode-gate-plugin/isolated-config`. Its checked-in
`opencode/plugins/commander-continuation.ts` entry re-exports only this
repository-local continuation plugin, without reading or modifying a user's global
configuration. Production uses the operator-managed global plugin directory above.

The pinned-release test records the expected server-only plugin registration and
exercises the trusted lifecycle: tool context -> persisted provenance -> exact
session follow-up -> idempotent retry/conflict rejection. It uses no provider
credentials or live user configuration.

The same plugin exposes `commander_list_projects` and
`commander_create_project_session`. The latter accepts only an ID returned by
the list tool, creates a normal session at that project's canonical directory,
and posts the requested text to that exact session with stable Commander
references. Its result includes an opaque `decision_id`; Commander must pass
that value, rather than a raw session or message ID, to
`commander_continue_agent` for a later exact-session follow-up. The plugin
persists the binding to the trusted Commander parent session and rejects a
reused create request with changed text. It neither selects a model nor makes a
provider call itself.

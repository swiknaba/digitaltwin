# DigitalTwin OpenCode server plugins

These are standard OpenCode v2.0.27 server plugins for the thin desktop client.
They are installed by an operator into an operator-owned global plugin directory;
they do not use project configuration, expose a renderer bridge, or read/write user
configuration. The helper creates symlinks only, so it never stores credentials.

```sh
OPENCODE_GLOBAL_PLUGIN_DIR=/operator-owned/opencode/plugins \
  sh commander/opencode-gate-plugin/install-future-tasks-plugin.sh
```

`future-tasks.ts` registers `future_tasks`. Its capability is supplied on every
tool invocation and is never persisted. The operator configures
`digitaltwinFutureTasksEndpoint` in the same global plugin registration; startup
rejects a missing, non-loopback HTTP, non-HTTPS, path-bearing, query-bearing, or
fragment-bearing value.

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

# Digitaltwin Commander Gate 1 probe

This minimal local OpenCode plugin tests only global-plugin loading. It has no UI
contribution code, no network calls, no custom tool, no model invocation, no
credential access, and no filesystem writes. It is intentionally insufficient to
pass Commander Gate 1.

`future-tasks.ts` is the separate native v2.0.27 global-plugin entry. It uses the
supported `Plugin.define` and `context.tool.transform(editor.add)` API to register
the `future_tasks` tool. Its one-use capability is supplied on each tool call, so it
stores no credential. The operator must supply the endpoint through the plugin's
`digitaltwinFutureTasksEndpoint` option; startup rejects a missing, non-loopback
HTTP, non-HTTPS, path-bearing, query-bearing, or fragment-bearing value. Install it
only in the operator-owned global plugin directory.

For a managed global plugin directory, the checked-in install helper creates only a
symlink and never writes a credential or project configuration:

```sh
OPENCODE_GLOBAL_PLUGIN_DIR=/operator-owned/opencode/plugins \
  sh commander/opencode-gate-plugin/install-future-tasks-plugin.sh
```

Configure `digitaltwinFutureTasksEndpoint` in that same operator-owned plugin
registration, then verify the plugin status using the release's plugin listing/API.
The tool itself accepts an optional `limit` for `list` whether or not a cursor is
provided.

OpenCode v2.0.27 rejected the current public-doc named-function shape. The probe
therefore uses the installed release's required default definition with an `id` and
`setup` function. That difference is recorded as Gate 1 evidence, not treated as a
stable product API.

## Installed local configuration

The enabled local installation is a symlink, not a copied plugin:

```text
~/.config/opencode/plugins/digitaltwin-commander-gate-probe.ts
  -> <digitaltwin worktree>/commander/opencode-gate-plugin/commander-gate-probe.ts
```

OpenCode loads global local plugins at startup. Restart the existing service after
installing or editing this probe:

```sh
/Applications/OpenCode.app/Contents/Resources/opencode-cli service restart
```

Successful loading is verified with:

```sh
/Applications/OpenCode.app/Contents/Resources/opencode-cli api GET /api/plugin
```

Find `digitaltwin-commander-gate-probe`; OpenCode v2.0.27 reports it active with
only `features.server: true`.
That result fails Commander Gate 1: the plugin does not prove, or expose a supported
path to, a Commander control, branded external conversation, remote-web UI surface,
reconnect behavior, or trusted bridge capability.

## Disable and restore

To disable the probe without touching any other OpenCode configuration, remove only
its symlink and restart the service:

```sh
rm ~/.config/opencode/plugins/digitaltwin-commander-gate-probe.ts
/Applications/OpenCode.app/Contents/Resources/opencode-cli service restart
```

The source stays in this directory for later manual testing. Do not copy API keys,
provider state, or credentials into this plugin.

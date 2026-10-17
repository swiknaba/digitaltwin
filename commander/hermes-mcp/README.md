# Hermes Commander delegation MCP

This is the native Hermes stdio MCP boundary for the four narrow Commander
delegation operations:

- `commander_list_projects`
- `commander_create_project_session`
- `commander_read_agent`
- `commander_continue_agent`

Its persisted decision state lives below `local/hermes/`. Create and continue
use deterministic message and decision identifiers, preserve a profile-level
Hermes provenance subject in OpenCode message metadata, and reject a changed
body for an existing request id. Read only requests existing session/message
data; it never posts a prompt.

`commander_create_project_session` and `commander_continue_agent` accept an
optional `worker_model` object (`provider_id`, `model_id`, and optional
`variant`). It is deliberately separate from Commander’s Hermes model. Before
creating a session or switching an existing worker, the bridge asks the target
project's OpenCode model endpoint for its enabled inventory and rejects a model
or variant not in that inventory. An explicit model is sent through OpenCode's
per-session API only: it never changes a project or global default. When
`worker_model` is omitted, OpenCode retains its normal project/default
resolution behavior.

OpenCode publishes its desktop sidecar through an owner-only
`service-local.json` registration, which is its supported local-client discovery
contract. The approved Hermes control bearer is not that credential and is never
repurposed for this bridge. Until an owner explicitly provides the absolute
`DIGITALTWIN_OPENCODE_SERVICE_REGISTRATION_FILE` path to the MCP process,
project operations fail closed before any request is sent to OpenCode. The MCP
`initialize` and `tools/list` handshake remains usable without that path.

When authorized, the bridge accepts only a current-user-owned, non-symlink
`service-local.json` with no group or other permissions. It verifies the
registration's loopback endpoint, normalizing only the desktop service's literal
`0.0.0.0` wildcard bind to `127.0.0.1`, then Basic-authenticates `/api/info`.
The discovered password is used only in memory for that request. A 401 causes
one fresh registration discovery, so a desktop restart can rotate its credential
without a copied password or persisted bridge secret.

Run `sh scripts/local-hermes-model` to open Hermes' interactive provider/model
picker with `HOME`, `HERMES_HOME`, caches, and runtime state pinned below this
checkout. It does not start the gateway or read its control bearer. Do not run it
until the owner is ready to configure a provider.

`profile-fragment.yaml` specifies the restricted server and exact tool allowlist
for the project-local profile. Its launcher resolves the checkout from the
`DIGITALTWIN_REPO_ROOT` environment that `scripts/local-hermes-gateway` exports,
so the same fragment works in the validation checkout and a moved worktree. It
does not alter `platform_toolsets`, so an operator's existing Hermes tool choices
are not overwritten.

The runtime keeps MCP support optional. Before registering this server with the
gateway, run `sh scripts/local-hermes-mcp-install`; it installs the pinned
Hermes `mcp` extra only under `local/hermes/runtime/`.

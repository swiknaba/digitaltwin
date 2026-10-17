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

The normal OpenCode desktop sidecar accepts its own private Basic password. The
approved Hermes control bearer is not that password and is never repurposed for
this bridge. Until an owner explicitly provides
`DIGITALTWIN_OPENCODE_SIDECAR_PASSWORD` to the MCP process, project operations
fail closed before any request is sent to OpenCode. The MCP `initialize` and
`tools/list` handshake remains usable without that password.

`profile-fragment.yaml` specifies the restricted server and exact tool allowlist
for the project-local profile. Its launcher resolves the checkout from the
`DIGITALTWIN_REPO_ROOT` environment that `scripts/local-hermes-gateway` exports,
so the same fragment works in the validation checkout and a moved worktree. It
does not alter `platform_toolsets`, so an operator's existing Hermes tool choices
are not overwritten.

The runtime keeps MCP support optional. Before registering this server with the
gateway, run `sh scripts/local-hermes-mcp-install`; it installs the pinned
Hermes `mcp` extra only under `local/hermes/runtime/`.

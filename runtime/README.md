# Agent Runtime

Non-root image containing Herdr, Codex CLI, Claude Code, OpenCode, Gemini CLI, Wagglebot, OpenSSH, and the required Linux tools.
Own Dockerfile, entrypoint, `tools.lock.yml`, Node pin, provisioning, and `bin/runtime-smoke` here.
Herdr and agent CLIs remain upstream dependencies.

## API and Configuration Contract

- Expose Herdr only through a task-local Unix socket shared with Kirei's worker.
- Preserve `/workspace/repos` and `/workspace/worktrees/<workflow-uuid>` on one workspace volume.
- Persist Herdr/configuration/login state as specified; backups exclude CLI logins and workspaces.
- Package Kirei-owned callback and MCP clients from their single source. Give agents no Mattermost bot credentials.
- Use non-root UID/GID, no Docker socket, no privileged mode, no host root mount, and only required capabilities/volumes.
- Provide private Tailnet terminal access; expose no public Runtime SSH port.

[Herdr's official socket documentation](https://herdr.dev/docs/socket-api/) provides `herdr api schema --json` from the installed binary.
Capture that schema at the selected exact release before implementing adapters.
Documented methods and effective states are candidates for validation, not proof that four CLIs settle reliably in our container.
See [shared boundaries](../docs/interfaces/service-boundaries.md) for callback, startup, socket, and validation ownership.

## Worker Scope

Prepare exact dependency provenance, base-image comparison, and Task 6 tool/image checks.
Task 1's required live evidence must pass before dependent sessions/review implementation.
Coordinate Kirei's sessions schema and Herdr adapter with its owner.
Prefer Alpine only after required dependencies work; record failures before any permitted fallback.

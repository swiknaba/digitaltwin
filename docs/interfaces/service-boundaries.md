# Service boundaries

| Producer → consumer | Boundary |
| --- | --- |
| OpenCode project session → Git | Upstream OpenCode owns project prompts, agents, workspaces, and repository feedback. Kirei is not on this path. |
| OpenCode Commander panel → Commander bridge | The maintained panel exposes typed open/send/steer/cancel/reconnect actions and sanitized events only. |
| Commander bridge → Kirei FutureTasks | A future-task capability creates, reads, updates, cancels, or records a disposition. It never writes queue rows directly. |
| Kirei worker → Commander bridge | A due execution supplies its existing immutable delivery key. Unknown delivery becomes `uncertain`; no new-key blind retry is permitted. |
| Kirei → PostgreSQL | Clean greenfield FutureTasks and retained jobs/audit tables. There is no Mattermost role, database, inbox, outbox, transcript, or workflow schema. |

The repository does not yet contain a production Commander bridge delivery adapter,
capability issuer, MCP tool, or OpenCode global tool. The current gateway fails closed
without operator-owned runtime wiring. That preserves the required boundary without
claiming Gate 1 or production connectivity.

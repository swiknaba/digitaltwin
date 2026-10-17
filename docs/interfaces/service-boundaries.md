# Service boundaries

| Producer → consumer | Boundary |
| --- | --- |
| OpenCode project session → Git | Upstream OpenCode owns project prompts, agents, workspaces, and repository feedback. Kirei is not on this path. |
| OpenCode Commander panel → OpenCode main process | The maintained panel reports normal sidecar availability only; endpoint headers remain in the main process. |
| Commander → Kirei FutureTasks | One-use capability API creates, pages, reads, updates, cancels, or records a disposition. It derives the actor from the capability and records Commander conversation only as provenance; it never writes queue rows directly. |
| Kirei worker → OpenCode session API | The configured normal-session client uses an immutable delivery key as its deterministic input id. Unknown delivery becomes `uncertain`; reconciliation queries/retries that same key, never a new-key blind retry. |
| Kirei → PostgreSQL | Clean greenfield FutureTasks, capability-use, and jobs tables. There is no Mattermost role, database, inbox, outbox, transcript, or workflow schema. |

The repository contains a configurable normal OpenCode-session client and thin
MCP/OpenCode tool adapters, but no capability issuer or live operator authorization.
Missing operator file-backed configuration fails closed.
This is not Gate 1 or production-connectivity evidence.

# Service boundaries

| Producer → consumer | Boundary |
| --- | --- |
| OpenCode project session → Git | Upstream OpenCode owns project prompts, agents, workspaces, and repository feedback. Kirei is not on this path. |
| OpenCode Commander panel → Commander bridge | The maintained panel exposes typed open/send/steer/cancel/reconnect actions and sanitized events only. |
| Commander bridge → Kirei FutureTasks | One-use capability API creates, reads, updates, cancels, or records a disposition. It derives actor/conversation from the capability and never writes queue rows directly. |
| Kirei worker → Commander bridge | The configurable private client supplies its existing immutable delivery key. Unknown delivery becomes `uncertain`; reconciliation queries/retries that same key, never a new-key blind retry. |
| Kirei → PostgreSQL | Clean greenfield FutureTasks, capability-use, and jobs tables. There is no Mattermost role, database, inbox, outbox, transcript, or workflow schema. |

The repository contains configurable private bridge-client and thin MCP/OpenCode tool
adapters, but no capability issuer, bridge deployment, or trusted OpenCode extension
exchange. Missing operator file-backed configuration fails closed. This is not Gate 1
or production-connectivity evidence.

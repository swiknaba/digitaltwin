# Commander flow and storage audit — 2026-10-16

## Scope and evidence

This is a source/schema audit of the pinned OpenCode `v2.0.27` checkout and the
greenfield Kirei migration. It does not read user configuration, credentials, or
session content. The identified session, `ses_eba1c99e0ffeNc5y6GCpivdEGp`, was
reported by the operator as successfully created. Its presence in OpenCode was
not queried from this audit environment.

The current product specification remains the authority: OpenCode owns normal
sessions and their history; Kirei owns only durable one-time future commitments.
The empty Kirei `jobs` table is therefore not evidence of a lost OpenCode
session.

## Storage ownership

| Concern | Implemented storage | Relevant fields | Assessment |
| --- | --- | --- | --- |
| OpenCode session and transcript | OpenCode's SQLite session store | `session_v2.id`, `project_id`, `directory`, `agent`, `model`, metadata; `session_message.session_id` and JSON `data`; inbox/pending rows reference `session_id` | Correct owner. `ses_…` is an OpenCode identifier, not a Kirei row. |
| Global Commander identity and selected Commander model | OpenCode desktop extension store | `CommanderBridgeState.conversation = { serverID, sessionID, directory, agent }`, optional `model` | Correct narrow identity store. The model is separate from normal OpenCode model preferences. The overlay did not restore it yet; correction is pending. |
| Native subagent continuation binding | OpenCode plugin storage | `digitaltwin.commander.decision.<decision-id>` → `{ parent, parentMessage, child, project, requests }` | Correct for a native `subagent` result. It protects exact parent/child continuation and tracks request digest idempotency. |
| Direct Commander-created project session | OpenCode's normal session store plus plugin storage | normal OpenCode session; plugin stores a parent-bound opaque `decision_id` and direct-create request digest | Corrected in this change. Existing sessions created before the correction have no direct-session reference to recover. |
| Future commitment | Kirei PostgreSQL | `future_tasks`, `future_task_executions`, `future_task_delivery_attempts`, `future_task_dispositions`, `jobs`, `future_task_capability_uses` | Correctly separate from OpenCode session storage. |
| Future-task source context | `future_tasks.origin` | capability-derived `conversation_id`, currently `opencode:<session-id>` | The originating conversation is retained as a string origin; there is no `session_id` column and no transcript/session mirror. |

The single migration, `integration-backend/db/migrate/001_future_tasks.rb`,
creates only the five FutureTasks tables above plus `jobs`. None contains an
OpenCode session column. `jobs` holds due/reconcile/outcome work only and stays
empty until a future task is created. It is not a session registry.

## Flow matrix

| Requirement | Implemented path | Persisted data | Gap / simplest correction |
| --- | --- | --- | --- |
| One global Commander conversation; keep current project visible | titlebar command → extension `reserve` → native sidecar `session.create/sync` → app-hosted native composer/timeline | extension `conversation` identity, full Commander session in OpenCode | Implemented. Live desktop behavior remains an operator validation gate. |
| Explicit Commander model, independent of normal model preferences | native `ModelSelectorPopover` uses visible native models; bridge `selectModel` saves a Commander-scoped selection | optional extension-store `model` | The renderer now sends the saved model, but the pending patch must cover hydration/reopen with a focused test. No global preference write is required. |
| Human prompt to Commander is a normal human prompt | native composer → Commander session API | OpenCode user message | Implemented. It must **not** receive `fromCommander`; that marker describes Commander-to-agent inputs. |
| Start project work from Commander | `commander_list_projects` → `commander_create_project_session` → `context.session.create` + `context.session.prompt` | normal child/project session and first message in OpenCode; first message carries `fromCommander: true`; a parent-bound `decision_id` in plugin storage | Corrected in this change. A repeat request with the same parent/project/request ID reuses the existing reference; changed text is rejected. |
| Follow up with the exact session Commander started | native subagent or direct project session: persisted decision ID → `commander_continue_agent` → exact `context.session.prompt` | plugin decision mapping and request digest | Corrected for future direct-created sessions. The old create result was not a native-subagent decision, so passing its `message_id` was rejected even when its `session_id` was correct. |
| Deterministic, restart-safe references | native subagent decision ID and direct project-session decision ID are derived from trusted tool context; future delivery input IDs are deterministic | plugin storage; Kirei delivery keys / receipts | Corrected for direct creates. The tool does not accept arbitrary model-supplied session IDs. |
| Every Commander-originated agent input is attributed | direct-create and native-decision continuation call `context.session.prompt` with `fromCommander: true`; Kirei gateway does likewise | OpenCode input/message metadata | Implemented on existing agent-input paths. Keep it out of the Commander overlay submission. |
| Read/result tracking | native OpenCode session/message APIs and timelines are authoritative | OpenCode session/message rows | Commander can inspect its own transcript. There is no explicit result-link/read API for a direct project session in the plugin; add it only if Commander needs to retrieve target status/transcript through a constrained reference, rather than mirroring content into Kirei. |
| One-time scheduling; retry/recovery; successor tasks instead of a recurrence engine | OpenCode global tool → signed capability → Kirei `CapabilityApi` → FutureTasks domain/worker → exact Commander session prompt | task, execution, attempt, receipt, disposition, queue job, nonce-use rows | Backend implements one-time states, delivery keys, reconciliation, and disposition. The shipped plugin currently exposes create/list/read/update/cancel only; it omits `disposition` and uncertain-resolution despite the backend routes supporting both. |
| Scheduled work stays a check-in, not automatic project work | Kirei gateway appends a visible Commander input | receipt records deterministic Commander input ID | Implemented in backend. Live authorization/sidecar delivery remains an operator check. |

## Findings

1. The report that the session ID was correct is compatible with the failure.
   `commander_continue_agent` does not take a session ID; it takes a persisted
   native-subagent decision ID. The direct-create tool returned a message ID,
   not such a decision. The rejection is therefore an interface mismatch, not
   evidence that it targeted the wrong OpenCode session. The newly-created
   direct-session reference fixes this for subsequent sessions; it cannot infer
   a safe opaque reference for the already-created session.
2. The current direct-create path bypasses Kirei by design. That is correct for
   ordinary agent work, but it means Postgres cannot be used to find or repair
   `ses_eba1c99e0ffeNc5y6GCpivdEGp`.
3. The repository has two continuation implementations: the active global
   OpenCode plugin and an `@digitaltwin/commander-bridge` workspace package.
   The workspace package has tests but no production importer outside itself;
   the active behavior is the plugin. This duplication risks documentation/tests
   proving a path that the running plugin does not use.
4. The specification is not incomplete about storage ownership. Its intended
   "exact runtime/project/session/source-message references" requirement is
   incompletely implemented for direct project-session creation.

## Recommended minimal sequence

1. **Completed:** plugin-owned opaque direct-session references now store the
   Commander parent session, source message, project, child session, and
   request digest. `commander_continue_agent` validates the caller and posts
   to that exact child with `fromCommander: true`.
2. **Completed:** direct-create retry/conflict, wrong-parent, restart recovery,
   and direct-reference follow-up regression tests cover the new path.
3. Remove or clearly demote the unused bridge-package continuation duplicate.
4. Complete the independent Commander-model hydration patch and test it. Extend
   the FutureTasks plugin to expose disposition/resolution only after confirming
   the desired operator workflow; this is a real API-surface deviation, not a
   reason to add a recurrence engine or session mirror.


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
| Global Commander identity and selected Commander model | OpenCode desktop extension store | `CommanderBridgeState.conversation = { serverID, sessionID, directory, agent }`, optional `model` | Correct narrow identity store. The model is separate from normal OpenCode model preferences. Patch 0025 restores it into the native composer on reopen. |
| Native subagent continuation binding | OpenCode plugin storage | `digitaltwin.commander.decision.<decision-id>` → `{ parent, parentMessage, child, project, requests }` | Correct for a native `subagent` result. It protects exact parent/child continuation and tracks request digest idempotency. |
| Direct Commander-created project session | OpenCode's normal session store plus plugin storage | normal OpenCode session; plugin stores a parent-bound opaque `decision_id` and direct-create request digest | Corrected in this change. Existing sessions created before the correction have no direct-session reference to recover. |
| Future commitment | Kirei PostgreSQL | `future_tasks`, `future_task_executions`, `future_task_delivery_attempts`, `future_task_dispositions`, `jobs`, `future_task_capability_uses` | Correctly separate from OpenCode session storage. |
| Future-task source context | `future_tasks.origin` | capability-derived `conversation_id`, currently `opencode:<session-id>` | The originating conversation is retained as a string origin; there is no `session_id` column and no transcript/session mirror. |

The single migration, `integration-backend/db/migrate/001_future_tasks.rb`,
creates `jobs`, `future_tasks`, `future_task_executions`,
`future_task_delivery_attempts`, `future_task_dispositions`, and
`future_task_capability_uses`. None contains an OpenCode session column. `jobs`
holds due/reconcile/outcome work only and stays empty until a future task is
created. It is not a session registry.

The active continuation plugin stores its records in the OpenCode SQLite `kv`
table, not in a standalone file or Postgres. OpenCode namespaces plugin keys;
the logical keys are `digitaltwin.commander.decision.<decision-id>` and
`digitaltwin.commander.project-request.<digest>`. Their exact physical database
path is operator-configurable (`OPENCODE_DB`); the normal CLI default is beneath
OpenCode's XDG data directory. Records have no explicit expiry or pruning path,
so they survive a normal server restart as long as that database remains.

## Flow matrix

| Requirement | Implemented path | Persisted data | Gap / simplest correction |
| --- | --- | --- | --- |
| One global Commander conversation; keep current project visible | titlebar command → extension `reserve` → native sidecar `session.create/sync` → app-hosted native composer/timeline | extension `conversation` identity, full Commander session in OpenCode | Implemented. Live desktop behavior remains an operator validation gate. |
| Explicit Commander model, independent of normal model preferences | native `ModelSelectorPopover` uses visible native models; bridge `selectModel` saves a Commander-scoped selection | optional extension-store `model` | Implemented by patch 0025, with a focused bridge-state persistence test. No global preference write is required. |
| Human prompt to Commander is a normal human prompt | native composer → Commander session API | OpenCode user message | Implemented. It must **not** receive `fromCommander`; that marker describes Commander-to-agent inputs. |
| Start project work from Commander | `commander_list_projects` → `commander_create_project_session` → `context.session.create` + `context.session.prompt` | normal child/project session and first message in OpenCode; first message carries `fromCommander: true`; a parent-bound `decision_id` in plugin storage | Corrected in this change. A repeat request with the same parent/project/request ID reuses the existing reference; changed text is rejected. |
| Follow up with the exact session Commander started | native subagent or direct project session: persisted decision ID → `commander_continue_agent` → exact `context.session.prompt` | plugin decision mapping and request digest | Corrected for future direct-created sessions. The old create result was not a native-subagent decision, so passing its `message_id` was rejected even when its `session_id` was correct. |
| Deterministic, restart-safe references | native subagent decision ID and direct project-session decision ID are derived from trusted tool context; future delivery input IDs are deterministic | plugin storage; Kirei delivery keys / receipts | Corrected for direct creates. The opaque `decision_id` is an implementation choice: the specification requires exact references, not this particular token format. It prevents arbitrary model-supplied session routing. |
| Commander-originated agent-input attribution | direct-create and native-decision continuation call `context.session.prompt` with `fromCommander: true` and a `Commander-directed work:` text prefix; Kirei gateway does likewise with a `Commander-directed scheduled check-in:` prefix | OpenCode input/message metadata and user-message text | The text prefix is agent-readable and transcript-visible; metadata remains durable provenance. The human-to-Commander overlay submission remains unmodified. |
| Read/result tracking | `commander_read_agent` resolves the same exact continuation reference, then reads the target session and latest assistant result through native OpenCode session APIs | OpenCode session/message rows | Implemented with constrained parent-bound reference lookup. Fixture coverage exists; no live target session was read. |
| One-time scheduling; retry/recovery; successor tasks instead of a recurrence engine | OpenCode global tool → signed capability → Kirei `CapabilityApi` → FutureTasks domain/worker → exact Commander session prompt | task, execution, attempt, receipt, disposition, queue job, nonce-use rows | Backend implements one-time states, delivery keys, reconciliation, and disposition. The global plugin now exposes disposition and uncertain-resolution routes; no authenticated end-to-end delivery was run. |
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
3. The unused `@digitaltwin/commander-bridge` workspace continuation duplicate
   was removed. The active global OpenCode plugin is now the sole continuation
   implementation; its regression suite covers parent ownership, exact child
   routing, retry/restart recovery, duplicate direct-create requests, and result
   readback.
4. The specification is not incomplete about storage ownership. Its intended
   "exact runtime/project/session/source-message references" requirement is
   incompletely implemented for direct project-session creation. It does not
   mandate an opaque `decision_id`; that is the selected implementation for a
   trusted, opaque continuation handle.

## Acceptance cases still required

1. **Create → follow-up → read result:** create a project session, retain the
   returned reference, send a follow-up using that reference, then read the
   target session/result through an approved normal OpenCode session view. The
   first three operations have fixture coverage; no live target session was read.
2. **Restart recovery:** restart the OpenCode server, reuse the direct-session
   reference, and verify that the target session receives exactly one
   deterministic follow-up. Fixture coverage exists; no live operator session
   was restarted.
3. **Future task due → completion/recovery:** create a one-time task, confirm
   the due job appends exactly one Commander check-in, record a disposition, and
   exercise an interrupted delivery/reconciliation against an authenticated
   sidecar. The global tool exposes disposition/resolution, but no authenticated
   end-to-end delivery was run.

## Recommended minimal sequence

1. **Completed:** plugin-owned opaque direct-session references now store the
   Commander parent session, source message, project, child session, and
   request digest. `commander_continue_agent` validates the caller and posts
   to that exact child with `fromCommander: true`.
2. **Completed:** direct-create retry/conflict, wrong-parent, restart recovery,
   and direct-reference follow-up regression tests cover the new path.
3. **Completed:** removed the unused bridge-package continuation duplicate and
   its workspace dependency/import path. Patch 0026 also removes the obsolete
   extension-owned dialog; the app-owned native overlay remains the sole UI.
4. **Completed:** patch 0025 hydrates the independent Commander model and has a
   focused persistence test. Extend the FutureTasks plugin to expose
   disposition/resolution only after confirming the desired operator workflow;
   this is a real API-surface deviation, not a reason to add a recurrence engine
   or session mirror.

## Validation update

The active plugin's focused suite passes seven tests, including a request-level
contract test for `create`, `disposition`, and `resolve_uncertain`. It verifies
the exact Kirei paths and JSON bodies and decodes each generated capability to
confirm the `opencode:<Commander session>` conversation scope. The full
OpenCode workspace typecheck passes after removal of the stale workspace.

The project-local Playwright Chromium cache is installed, but the pinned
Storybook 10.4.4 server aborts before serving with `Invariant failed: expected
options to have a port` under both Bun and Node even with `--port 6006`.
Therefore no browser click/type pixel assertion is claimed from this run; that
runner failure must be corrected before the native overlay visual regression can
execute.


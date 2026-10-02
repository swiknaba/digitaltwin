# Integration Backend

Ruby modular monolith for authenticated chat routing, durable jobs, workflows, reviews, Master operations, and delivery.
One image runs `bin/web`, `bin/worker`, and `bin/chat-listener` separately.
Own source, Gemfile/lockfile, Ruby `4.0.7` pin, migrations, component tests, Dockerfile, and callback/MCP clients here.

## API and Configuration Contract

- Reuse generated `GET /livez` and `GET /readyz`. Readiness checks PostgreSQL; pending migrations block process startup.
- Use a dedicated PostgreSQL database/role. Never read or migrate Mattermost tables.
- Consume authenticated Mattermost REST/events; persist verified channel/root/post/sender identity before dispatch.
- Access Herdr through the worker/Runtime shared Unix-socket volume on the same host/task.
- Accept private, session-bound `digitaltwin say`, artifact-ready, and review-ready callbacks.
- Derive destination, role, and bot identity server-side. Deduplicate session/generation/key; reject changed bodies and stale generations.
- Provide the stdio `bin/mcp` bridge to existing typed services, with verified actor/channel/thread context and confirmation checks.

Wire routes, payload schemas, secret-file names, port, and UID/GID need explicit agreement before adapters consume them.
See [shared boundaries](../docs/interfaces/service-boundaries.md) for open gates and ownership.
Shared entities and migrations remain in Kirei, not a second contract service.

## Worker Scope

The Kirei 0.10.0 CLI generated the scaffold now in this folder from an empty staging directory.
Finish the dependency lock, Linux platforms, startup entry points, and tests under the required Ruby 4.0.7.
See `bootstrap.lock.json` and the [foundation checkpoint](../docs/interfaces/foundation-validation.md).
Implement Tasks 2-5 before dependent workflow/review/Master/delivery work in Tasks 7-11.
The integrator reviews Compose/root/shared-contract changes. Runtime owns image provisioning, not this application's sessions migration or adapter.
Keep component tests in `spec/`; cross-deployable acceptance belongs in root `tests/`.

## Numbered Migrations

Use contiguous `001_jobs.rb` through `006_confirmations.rb` and subsequent numbered files.
Tasks use Sequel's IntegerMigrator and `schema_info.version`; no timestamp migration metadata is required.
`db:migration[name]` generates the next three-digit prefix; `db:status` reports the current version.
`db:rollback` defaults to one step. Positive `STEPS` values can roll back several versions, including the last migration to zero.

The focused regression suite is `spec/integration/db_tasks_spec.rb`.
Set `MIGRATION_TEST_DATABASE_URL` to a disposable database named `digitaltwin_migration_test` and run it through RSpec.
It exercises the actual Rake helper against PostgreSQL with a fixture bootstrap; it does not claim full application boot.

## Why this exists

Kirei keeps routing, authorization, durable jobs, and revision gates in one Ruby application.
Sequel and PostgreSQL provide explicit transactions and durable recovery without a second queue service.
Falcon serves the web role after request isolation and input compatibility checks.
The worker and listener run independently so reconnects and network calls do not block web startup.
They share one image and schema. Mattermost and the agent Runtime remain separate because they own different state and lifecycles.
Replace this control plane if a future chat/runtime platform provides these verified gates and recovery guarantees.
A web server change can replace Falcon without changing the application boundaries.

## Implemented foundation

The image runs Ruby 4.0.7, Kirei 0.10.0, Falcon 0.57.0, and the exact dependencies in `Gemfile.lock`.
Build with `docker build -t digitaltwin-backend integration-backend` from the repository root.
For the host target, add `--platform linux/amd64`.
Run `bundle exec rake db:migrate` from this folder before starting any role.
All roles reject pending numbered migrations; none migrate at startup.

`bin/web` serves the generated health routes and private `POST /internal/callbacks/say`.
Kirei's router environment is fiber-local and cleared after requests.
JSON bodies are bounded at 64 KiB and normalized to StringIO for Kirei's parser.
`bin/worker` claims durable jobs, renews leases, and blocks unconfigured effects.
`bin/chat-listener` authenticates WebSocket ingestion and refetches identities through REST before durable routing.
The listener and Mattermost delivery handler require `CHAT_VALIDATION_MODE=1` for disposable validation.
That mode does not enable agent sessions, reviews, approvals, Master MCP, or production workflows.

Migrations `001`-`008` provide jobs/inbox/outbox/audit, projects, and preparatory sessions/workflows/reviews/confirmations storage.
`Domains::Workflows::Entities` owns the typed shared contracts.
`Policy` contains pure approval/diversity/settled-state checks; it is not an enabled workflow coordinator.
Enrollment and Git worktree services validate explicit channel mappings, remote identities, branches, and real paths.
Live GitHub creation needs an operator-provided `gh` executable and authentication; neither is baked into the image.
Clone access uses the operator's external Git credential configuration.
No network operation runs inside a database transaction.

## Process configuration

| Setting | Contract |
| --- | --- |
| UID/GID | `10001:10001` for all backend roles; matches Runtime worker socket owner |
| `DATABASE_URL` | Dedicated Kirei PostgreSQL role/database; required |
| `DB_POOL_SIZE`, `DB_POOL_TIMEOUT` | Defaults `5`, `2` seconds; positive bounded pool; connection timeout 5 seconds |
| SQL bounds | Statement timeout 10 seconds; lock timeout 2 seconds |
| `PORT`, `WEB_PROCESSES` | Web defaults `3000`, `1`; HTTP private/TLS termination belongs to infrastructure |
| `WORKSPACE_ROOT`, `WORKTREE_ROOT` | `/workspace/repos`, `/workspace/worktrees`; shared Runtime workspace mount required for enrollment |
| `MATTERMOST_URL` | Private HTTP(S) server base, without API suffix |
| `MATTERMOST_LISTENER_TOKEN_FILE` | Read-only mounted listener credential; never a token value in Git |
| `MATTERMOST_WORKER_TOKEN_FILE`, `MATTERMOST_AGENT_TOKEN_FILE` | Read-only bot credential files for validation delivery |
| `MATTERMOST_WORKER_BOT_ID`, `MATTERMOST_AGENT_BOT_ID` | Exact configured identities; checked against authenticated `/users/me` |
| `MATTERMOST_LOCAL_BOT_IDS`, `MATTERMOST_PEER_BOT_IDS` | Comma-separated identities excluded from human authority; listener requires local IDs |
| `MATTERMOST_CHANNEL_IDS` | Explicit monitored channel IDs; no inferred channel-name/repository mapping |
| `AGENT_HANDLE`, `WORKER_HANDLE` | Defaults `agent`, `worker` |
| `CHAT_VALIDATION_MODE` | `1` permits disposable chat transport checks; absent keeps delivery/listener closed |
| Health | `bin/health web`, `bin/health worker`, `bin/health chat-listener`; Compose must override the image's web probe per role |
| `HEARTBEAT_DIR` | Default `/tmp`; worker and chat-listener touch `digitaltwin-<role>.heartbeat` there, and `bin/health` fails when it is missing or older than 60 seconds; backend image contains no provider login state |
| Herdr | Agreed `/run/herdr/herdr.sock`, mode 0600, UID 10001; adapter still gated on provider evidence |

Web startup checks schema in the parent, disconnects its database, and creates independent pools in Falcon children.
Worker/listener each own their Async reactor. HTTP calls own and close their client and response and disable automatic retries.
Unknown external effects become `uncertain`; they require positive reconciliation evidence or human direction.
The outbox never assumes exactly-once network delivery.

## Standalone Runtime clients and Master routing

`bin/digitaltwin` supports say, artifact-ready, review-ready and master-reply using Ruby stdlib.
`bin/mcp` plus the two standalone bridge modules provide request-bound stdio tools over private HTTP.
Runtime stages only the checksum-manifest files; no app bundle, database or provider credentials.
Callbacks use session Bearer capabilities and generation; Master tools/replies use a separate short-lived
request capability. HTTP queues artifact/review callbacks and controls for worker Git/socket checks.

Master-chat requests use configured trusted role profiles and recent accessible task evidence.
Typed tools list projects/workflows/context, start workflows, route follow-ups and queue exact-version
controls. Ambiguity requires clarification; explicit `@agent route WORKFLOW_ID` plus newline/instruction
remains available. Requests serialize on one Controller conversation; expired/uncertain requests require
exact same-human `@agent recover-master REQUEST_ID`. Replies deduplicate and cannot change on replay.

Thread provisioning verifies bot/channel/root identity before binding isolated worktrees and role sessions.
The captured Herdr adapter maps workspace.create, agent.start/get/prompt and pane.close. Missing/replaced
identities and uncertain effects block. No blind restart or resend occurs. Credential files are runtime-only,
mode0600, with identity/source/digest-verified renewal against the same conversation.

Review-ready freezes exact clean commits, validates diverse Reviewer identity and append-only review
changes, and durably queues release/corrective prompts. Pause/resume retains revision/version binding;
finish requires delivered work and archives only after confirmed role stops. Exact human Master-chat
approval advances through independent review/current-tree checks; changed approved artifacts fail closed.

`ROLE_CONFIG_FILE` supplies trusted controller/writer/reviewer cli/provider/model/family/launch_args.
Operator overlays must provide existing verified bot/token references to the appropriate processes.
Only the worker mounts Git workspaces and the Herdr socket. No environment switch enables dispatch.
All positive lifecycle tests inject fixture policy; real `Policy#dispatch_allowed?` remains false.
New project enrollment through MCP, verified PR delivery/done transition and broader
operational/destructive MCP tools remain separate implementation and acceptance work.

## Checks and remaining gates

`bin/check` requires disposable databases named `digitaltwin_backend_test` and `digitaltwin_migration_test`.
Set `DATABASE_URL` and `MIGRATION_TEST_DATABASE_URL`, then run it from this folder.
It runs PostgreSQL/domain/Rack/actual-Falcon/local-HTTP fixtures, isolated migration-helper tests, the complete configured RuboCop suite, and whole-project Sorbet.
Generated Tapioca dependency RBIs are committed under `sorbet/rbi/gems` and are refreshed in the pinned Debian `typecheck` Docker target; that target is check-only because Tapioca's Ruby 4 helper requires glibc. The production runtime remains the pinned Alpine image and its dependencies remain musl-linked.
Run `docker build --target typecheck -t digitaltwin-backend-typecheck integration-backend` from the repository root to reproduce the full static checks, then run `docker run --rm -v "$PWD/integration-backend:/app" -w /app digitaltwin-backend-typecheck bundle exec tapioca gems` before committing dependency changes.

Mattermost fixtures are synthetic shapes audited against release `11.11.1`, commit `3acb3a7f684d11ccfcec4e5bd11c79f64e3eabf9`.
They are not authenticated server captures. REST may omit human `is_bot:false`; only refetched, identity-checked users use that default.
Server-side source pins and offline tests do not clear live authentication, bot permissions, WebSocket, or reconnect gates.
Ordinary bot backfill cannot promise deleted-post recovery: `include_deleted` is admin-gated, and the `since` path does not forward it.

Tasks 6-10 remain blocked on required authenticated chat/threads, CLI prompt/state/stop, Writer settled, and selected Master MCP evidence.
The early real mention → Herdr CLI → source-thread reply slice has not passed.
Provide operator-controlled disposable listener/bot accounts and provider test access to run those checks.
No production deployment, provider authentication, paid calls, signed-device push, or final Phase 0 acceptance is claimed.

Bounded receipt recovery and the exact minimum manual setup are documented in
[Master routing setup](../docs/interfaces/master-routing-setup.md). Startup/renewal follow-ups remain
bound and queued; human/remote evidence resolves uncertainty without repeating network effects.

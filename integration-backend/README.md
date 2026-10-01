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
Implement Tasks 2–5 before dependent workflow/review/Master/delivery work in Tasks 7–11.
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

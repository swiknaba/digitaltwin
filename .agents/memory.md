# Repository Memory

- Integration backend dependency loading is centralized in `app.rb`: Gemfile group selection is the only production, development, and test loading boundary. Do not use `require: false` in its Gemfile or explicit `require` calls in `integration-backend/app/`.
- Backend ids are random strings (human ids or UUIDs). Never infer chronology from id order. Order by `created_at` (or `round`/`generation`) with id only as a tie-break.
- The backend test suite uses one fixed database, `digitaltwin_backend_test`, and truncates all tables before each example. Never run two RSpec processes against it at once.
- Kirei has no advisory-lock or multi-model transaction API. `Platform::Lock` and `Platform::Transaction` are the only allowed users of `Kirei::App.raw_db_connection`.
- AgentsView's upstream MCP usage summary accepts date bounds but uses UTC and also exposes transcript tools. The planned Runtime integration therefore needs a narrow, backend-owned usage adapter for configurable local-time ranges.
- Commander knowledge is Hermes-native: Markdown memory, SQLite history, and learned skills live in the Commander profile. Kirei remains authoritative only for orchestration, sender provenance, authorization, sessions, jobs, routing, and approvals; it does not mirror Commander memory.
- Hermes reads the Wagglebot-provisioned shared worker library at `/home/runtime/.agents/skills`. This is separate from the Commander profile's memory, history, and learned skills.
- Herdr agent names must use lowercase letters, digits, and hyphens. Preserve a durable Kirei session id unchanged and use its deterministic hash as the runtime alias whenever the usual `digitaltwin-<session-id>` form is invalid.

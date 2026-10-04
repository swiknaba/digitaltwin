# Repository Memory

- Integration backend dependency loading is centralized in `app.rb`: Gemfile group selection is the only production, development, and test loading boundary. Do not use `require: false` in its Gemfile or explicit `require` calls in `integration-backend/app/`.
- Backend ids are random strings (human ids or UUIDs). Never infer chronology from id order. Order by `created_at` (or `round`/`generation`) with id only as a tie-break.
- The backend test suite uses one fixed database, `digitaltwin_backend_test`, and truncates all tables before each example. Never run two RSpec processes against it at once.
- Kirei has no advisory-lock or multi-model transaction API. `Platform::Lock` and `Platform::Transaction` are the only allowed users of `Kirei::App.raw_db_connection`.

- The app is undeployed. Naming cleanup updates source, schema definitions, clients, and documentation together; validate from an empty disposable database.

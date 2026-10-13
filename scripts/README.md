# Repository scripts

These commands support the OpenCode-first local boundary. OpenCode and any
Commander runtime are operator-managed; this repository's default Compose stack is
only Kirei plus PostgreSQL.

`acceptance` reads public `.env.example` values and never reads an operator `.env`.

- `config` validates the default Compose graph without starting containers.
- `dependencies` starts a generated disposable PostgreSQL project, verifies Kirei's
  database identity, and removes that project's resources.
- `operator` prints the remaining runtime, OpenCode, and FutureTasks acceptance
  work without starting anything.

`dev` preserves an existing ignored `.env` or creates one from `.env.example`, then
starts the Kirei/PostgreSQL stack. It never stages callback clients, starts a chat
service, or configures agent credentials.

`init-postgres.sh` runs only on an empty local PostgreSQL volume. It creates the
single Kirei role and `digitaltwin_development` database; it does not create a
Mattermost role or database.

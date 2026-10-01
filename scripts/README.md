# Repository Scripts

Non-deployable commands for local setup, acceptance orchestration, and infrastructure handoff preparation.
Application process commands stay in their component folders.

## API and Configuration Contract

Commands must document arguments, required environment, exit codes, and external effects.
Keep repository checks independent of real credentials where possible.
`scripts/acceptance` uses Python's standard library and Docker Compose; it reads public `.env.example` values only.
It ignores ambient Compose overrides and database passwords. It never reads the operator's `.env`.

- `config`: validate dependency Compose and the opt-in backend overlay. Start nothing; return JSON evidence.
- `dependencies`: create a unique disposable project, check both database identities and denied cross-database connections, and verify Mattermost ping/version.
  Publish Mattermost on a random loopback port. Remove the project's containers and volumes, including on failure.
  Leave Docker, cached images, and other projects alone. Use only checked-in sample passwords; create no user or bot accounts.
- `operator`: print remaining live gates; start nothing and create no credentials.

Exit `0` means the selected check passed; exit `1` means failure. CLI misuse exits `2`.
Dependency mode starts Docker containers and may download the pinned images. Docker must already be available.
Cleanup failure reports the generated project name for manual removal. No service logs or resolved secret configuration enter evidence.
`config` and `dependencies` explicitly report `live_roundtrip: false`.
Production infrastructure provisioning remains separately authorized work in the infrastructure repository or hosting platform.

The integration owner owns this folder. Component workers propose shared script changes through that owner.

`init-postgres.sh` runs inside PostgreSQL on first volume initialization.
It consumes local application passwords from environment and creates separate Kirei/Mattermost roles and databases.
Live disposable PostgreSQL checks verified initialization, own-database connections, and both denied cross-database connections.

# Repository Scripts

Non-deployable commands for local setup, acceptance orchestration, and infrastructure handoff preparation.
Application process commands stay in their component folders.

## Why This Exists

Cross-service checks and setup need one owner and one command entry point.
Keeping them here avoids copying orchestration into independently built component images.

## API and Configuration Contract

Commands must document arguments, required environment, exit codes, and external effects.
Keep repository checks independent of real credentials where possible.
`scripts/acceptance` uses Python's standard library and Docker Compose; it reads public `.env.example` values only.
It ignores ambient Compose overrides and database passwords. It never reads the operator's `.env`.

- `config`: validate dependency Compose, the backend overlay, and the prepared combined overlay. Start nothing; return JSON evidence.
- `dependencies`: create a unique disposable project, check both database identities and denied cross-database connections, and verify Mattermost ping/version.
  Publish Mattermost on a random loopback port. Remove the project's containers and volumes, including on failure.
  Leave Docker, cached images, and other projects alone. Use only checked-in sample passwords; create no user or bot accounts.
- `operator`: print remaining live gates; start nothing and create no credentials.
- `stack --project NAME --runtime-service NAME --compose-file FILE ...`: inspect an already started, reviewed combined stack.
  Check backend health, socket UID/mode in both consumers, and JSON Herdr status. Create no accounts or sessions; change no container lifecycle.
  Complete Runtime wiring and component review are prerequisites. This mode is prepared but not yet verified against a combined stack.
- `runtime-offline`: start only reviewed Runtime and named-volume initialization in a generated disposable project.
  Verify native Herdr health/version/protocol and UID10001/mode0600 socket access from a second container; remove all project resources.
  Require `docker build --platform linux/amd64 --target offline -t digitaltwin-root-runtime-offline:check agent-runtime` first.
  Package no callback artifact, start no CLI/provider sessions, and claim no backend integration.

Exit `0` means the selected check passed; exit `1` means failure. CLI misuse exits `2`.
Dependency mode starts Docker containers and may download the pinned images. Docker must already be available.
Build the reviewed derived chat image with `docker compose --env-file .env.example build mattermost` before dependency mode.
`dependencies --derived-chat` also exercises prepared Runtime volume ownership through the combined overlay without starting Runtime/backend.
Cleanup failure reports the generated project name for manual removal. No service logs or resolved secret configuration enter evidence.
All executable check modes explicitly report `live_roundtrip: false`.
Production infrastructure provisioning remains separately authorized work in the infrastructure repository or hosting platform.

The integration owner owns this folder. Component workers propose shared script changes through that owner.

`prepare-callback-context` requires the reviewed/merged backend `bin/digitaltwin` with the Runtime-agreed SHA256.
It copies that single file into ignored `.local/kirei-clients/` for Runtime's `with-callback` named build context.
It refuses changed artifacts or extra context files. It creates no credentials or provider state; exit `1` indicates failure.
`init-local-volumes.sh` is the one-shot root initializer inside pinned BusyBox with no network.
It seeds chat config if absent and changes only mounted named-volume ownership; it does not rotate existing database roles or credentials.
The combined overlay opts into Runtime volume initialization; the default initializes chat storage only.

`init-postgres.sh` runs inside PostgreSQL on first volume initialization.
It consumes local application passwords from environment and creates separate Kirei/Mattermost roles and databases.
Live disposable PostgreSQL checks verified initialization, own-database connections, and both denied cross-database connections.

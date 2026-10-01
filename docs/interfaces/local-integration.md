# Local Integration Contract

The integrator owns root Compose, environment, scripts, and shared contracts.
Component owners own image builds, startup commands, lockfiles, and component tests.

## Backend Agreement

`compose.backend.yml` prepares the backend owner's proposed contract:

- One `digitaltwin-integration-backend:local` image built from `integration-backend/`.
- UID/GID `10001:10001`; web port `3000`, published only on loopback.
- `DATABASE_URL` uses the Kirei role and `digitaltwin_development` database.
- `DB_POOL_SIZE=5`, `DB_POOL_TIMEOUT=2`, `RACK_ENV=development`, `PORT=3000`.
- One-shot `bundle exec rake db:migrate` completes before `bin/web`, `bin/worker`, and `bin/chat-listener` start.
- Web readiness probes `/readyz`; component startup must reject pending migrations independently of Compose.

The backend owner must verify these settings, image `net/http` availability, and entrypoint command forwarding.
Worker/listener process health and restart policies remain open until their failure/recovery contracts are tested.
No web server implementation is selected by this root overlay.

Mattermost uses native `/mattermost/bin/mmctl system status --local` health with local mode enabled.
The selected distroless image requires no shell or curl for this check.
Root configuration disables plugins, uploads, both marketplaces, and automatic prepackaged plugins.
The official image still contains prepackaged plugin archives. Their removal/audit belongs to the chat owner's derived-artifact handoff.
Do not claim commercial components are absent from the current upstream image.

Validate with `scripts/acceptance config`.
After the backend handoff, build with `docker compose --env-file .env.example -f compose.yml -f compose.backend.yml build`.
The overlay is preparation, not a complete roundtrip stack. Do not start worker/listener integration before the remaining contracts are wired.

## Contracts Needed Before Startup

| Owner | Required handoff to integrator |
| --- | --- |
| Runtime + backend | Verified socket contract below; image startup, volume initialization, health and reconnect behavior still need integration |
| Backend | Exact chat credential/config names, source identity mapping, callback route/auth schema, readiness and process health |
| Chat + backend | Authenticated event fixtures, local bot enablement/config, verified human/bot/channel/root/membership, REST reconnect behavior |
| Runtime + backend | Single-source callback/MCP packaging, runtime-to-backend private URL, real CLI test and selected Master MCP evidence |
| Push + mobile | Validated private server/proxy configuration and operator-owned app identities; device evidence remains separate |

No guessed socket path, auth variable, callback schema, or fabricated runtime replaces these handoffs.
Add a shared socket only to the worker and Runtime unless a verified consumer requires it.
Keep bot credentials outside Runtime. Publish no Runtime SSH port, Docker socket, or host root mount.

### Received Wire Contracts

- The backend owns standalone Ruby-standard-library `bin/digitaltwin`; Runtime installs it at `/usr/local/bin/digitaltwin`.
  It requires Ruby >=3.1, without Bundler or database access.
- `POST /internal/callbacks/say` accepts JSON `generation`, `key`, and `text`.
  The client reads a bearer token from `DIGITALTWIN_SESSION_TOKEN_FILE` and uses `DIGITALTWIN_CALLBACK_URL`.
  The backend derives destination and role; generation environment naming still needs the backend's exact handoff.
  Artifact callbacks and MCP remain disabled pending their live gates.
- Push listens privately on `8066` with command `-config /mattermost-push-proxy/config/mattermost-push-proxy.json`.
  `GET /version` proves process health only. Mattermost's configured base `http://push-proxy:8066` appends `/api/v1/send_push`.
  Native `AppleAuthKeyFile` and `ServiceFileLocation` point to mounted files; upstream provides no automatic `_FILE` resolver.
- Linux AMD64 Herdr 0.9.3 runs on stock Alpine 3.23 per the Runtime owner's preliminary check.
  `herdr server` runs in the foreground; `herdr status --json` reports compatible/running, version 0.9.3, protocol 22.
  `HERDR_SOCKET_PATH=/run/herdr/herdr.sock`, mode `0600`, requires shared UID `10001`.
  `herdr.client.sock` shares that directory; `HOME/.config/herdr` needs persistent storage.
  The backend-worker overlay mounts `herdr-socket` at `/run/herdr`; Runtime must mount the same volume and initialize ownership.
  Callback Ruby >=3.1 comes from Alpine independently of backend Ruby 4.0.7.
- Runtime packages unchanged Wagglebot 0.3 tarball content with separately locked skills 1.5.23.
  This addresses upstream npm `workspace:*` packaging failure without a downgrade; help is validated, live provider behavior remains open.

## Early Real Roundtrip

Use a uniquely named disposable local project and an otherwise empty test team/channel/thread.
Use existing operator-authorized credentials or fully disposable local fixture identities under the chat owner's approved test procedure.
Do not create persistent provider logins, paid sessions, production accounts, or external project changes.

1. Validate actual built backend/Runtime images, migrations, readiness, socket ownership, and Linux Herdr schema.
2. Verify authenticated human/bot identities, source channel membership, and the source root through Mattermost REST.
3. Send one unique test mention under the authenticated human identity.
4. Observe authenticated WebSocket ingestion, persisted inbox and queued dispatch, and one real CLI session through Herdr.
5. Verify one bot reply in the exact source channel/root and a completed outbox delivery.
6. Exercise an ordinary human reply without another mention and reconnect/backfill without duplicate delivery.
7. Capture sanitized component revisions, image identities, commands, event/job/session/outbox references, and pass/fail results.
8. Remove disposable accounts with their project data, local session state, containers, and volumes.

Never include tokens, provider login files, or private conversation bodies in evidence.
Report chat/API, queue, Herdr/provider, and outbox/thread observations separately.
Without the actual CLI execution, label the result a fixture/adapter check and keep the live slice open.
Dependency ping alone proves neither authenticated chat nor the early slice.

Four-CLI start/prompt/state/stop, Writer settled state, and selected Master MCP remain separate Task 1 gates.
Tasks 6–10 retain those gates. Signed-device push, restore, and production deployment retain their operator prerequisites.

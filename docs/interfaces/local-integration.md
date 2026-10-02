# Local Integration Contract

The integrator owns root Compose, environment, scripts, and shared contracts.
Component owners own image builds, startup commands, lockfiles, and component tests.

## Why This Exists

Component images meet at shared ports, volumes, identities, and credentials.
This agreement prevents independent workers from selecting incompatible values and separates local health from live workflow evidence.

## Backend Agreement

`compose.backend.yml` prepares the backend owner's proposed contract:

- One `digitaltwin-integration-backend:local` image built from `integration-backend/`.
- UID/GID `10001:10001`; web port `3000`, published only on loopback.
- `DATABASE_URL` uses the Kirei role and `digitaltwin_development` database.
- `DB_POOL_SIZE=5`, `DB_POOL_TIMEOUT=2`, `RACK_ENV=development`, `PORT=3000`.
- One-shot `bundle exec rake db:migrate` completes before `bin/web`, `bin/worker`, and `bin/chat-listener` start.
- Web readiness probes `/readyz`; component startup must reject pending migrations independently of Compose.

The backend owner must verify these settings, image `net/http` availability, and entrypoint command forwarding.
Worker/listener override the image's default web health with `bin/health worker` and `bin/health chat-listener`.
Their actual combined health and restart/failure recovery still need integration testing.
The listener requires opt-in profile `chat-validation`; credential-free startup excludes it.
Its profile sets `CHAT_VALIDATION_MODE=1` and private `MATTERMOST_URL`; missing approved token files and identity/channel mappings must fail startup.
Worker validation stays `0` by default, blocking unconfigured effects. An operator override must enable worker validation and mount bot credentials for transport/outbox checks.
Use the backend's documented `MATTERMOST_*_TOKEN_FILE`, bot/local/peer IDs, and channel-ID settings; Runtime receives no bot tokens.
No web server implementation is selected by this root overlay.

Mattermost uses native `/mattermost/bin/mmctl system status --local` health with local mode enabled.
The selected distroless image requires no shell or curl for this check.
Root configuration disables plugins, uploads, both marketplaces, and automatic prepackaged plugins.
The official upstream image contains prepackaged plugin archives; the reviewed chat-derived artifact removes all plugin bytes from final layers.
Root now builds that artifact by default and seeds writable UID2000 config storage.
The core binaries and 103 notices retain upstream hashes; full transitive-license permissibility remains open.

Validate with `scripts/acceptance config`.
After the backend handoff, build with `docker compose --env-file .env.example -f compose.yml -f compose.backend.yml build`.
The reviewed core is now in default `compose.yml`; `compose.backend.yml` and `compose.integration.yml` are compatibility no-ops.
The default excludes the authenticated listener and push. Core health does not establish the real provider roundtrip.

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
  `DIGITALTWIN_SESSION_GENERATION` supplies the integer generation; `DIGITALTWIN_CALLBACK_URL` is a private base URL, without a path.
  The backend derives destination and role. The client accepts only `say --text TEXT --key KEY` and expects HTTP `202`.
  Retry uncertain results with the same key; never print response bodies, headers, or credential values.
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
Tasks 6-10 retain those gates. Signed-device push, restore, and production deployment retain their operator prerequisites.

## Combined Local Check Preparation

After component review, the integrator merges prerequisite contracts and wires the actual Runtime image/startup.
Start a reviewed disposable stack under an explicit project name. Do not merge or build unreviewed component code for this check.
Run `scripts/acceptance stack --project <project> --runtime-service <service>` with repeated `--compose-file <file>` arguments for the complete stack.
The command observes existing containers only. It verifies backend health, the shared socket's UID/mode in both consumers, and JSON Herdr status.
It creates no accounts, sessions, or credentials and changes no container lifecycle.
This prepared command has not run against a combined stack; component merges and actual Runtime wiring remain prerequisites.
It always reports authenticated chat/provider/roundtrip as untested. The final independent integration worker owns broader acceptance after component integration.

### Prepared Combined Compose

Default `compose.yml` now contains the review-cleared service graph that passed independent local combined tests:

- Build the chat owner's minimal derived artifact; retain UID2000, native health, config/data/log volumes, and independent database ownership.
- A network-free one-shot initializer seeds partial chat config into writable storage and assigns named-volume ownership.
  It runs as root only for ownership changes; long-running Runtime/backend/chat/push processes keep their component UIDs.
- Build Runtime target `with-callback` from `agent-runtime/`, using named context `kirei-clients` from ignored `.local/kirei-clients/`.
  `scripts/prepare-callback-context` copies only the merged backend-owned client after its exact agreed SHA256 matches.
  Run this only after component review/merge; it creates no credentials and does not change component source.
- Persist Runtime home/workspace and share `/run/herdr` with the worker. Publish no Runtime ports or host mounts.
- Wait for healthy Runtime before worker startup, and healthy Mattermost before listener startup. Preserve the backend migration gate.
- Keep push/email disabled in chat. Optional `push` profile starts the private proxy with empty provider settings and process health only.
  Do not infer provider readiness from `/version` or enable delivery without approved credentials and matching app identities.

Use `scripts/dev` for local boot; it prepares public sample environment if absent and stages the callback before default Compose startup.
The previous backend/integration overlay paths remain as no-op compatibility files for existing test commands.
The promotion preserves the resolved service graph exactly, including every profile. Its default-entrypoint change requires an independent targeted rerun.
The reviewed chat build and disposable PostgreSQL/chat default passed root checks after its merge.
Runtime/backend build contexts, callback artifact packaging, combined first boot, and live callbacks remain unverified here.
Never reuse old plugin volumes. Retain approved production/credential setup as separate steps.

### Reviewed Runtime Root Check

The reviewed Runtime merge `11de3807052ff87c977ac4fdf622eb3472b9ae4b` is integrated locally.
Its explicit offline target built and passed `scripts/acceptance runtime-offline` with the root initializer and named volumes.
Herdr reported running/compatible version 0.9.3, protocol 22. A second UID10001 container accessed the mode0600 socket.
All disposable containers/volumes were removed. No backend, callbacks, CLI/provider sessions, or credentials were used.

The backend owner froze the formatted callback file at SHA256 `cd7dd6f80e050b91387c92fa285964f19ed089bb84b44c8dbb0dd5caf8478054`.
Root independently verified that supplied file hash and retained checksum enforcement.
The reviewed Runtime follow-up merged in `3a84f89d39353f526cf679df14f920504bffe45f` pins the same frozen artifact.
Root staging and Runtime checksum enforcement now match. Reviewed backend head `53c69b7d537b906a06303461c658f62b990f23d9`
is integrated through merge `0c79c77719713ca38417d5ea6da63ca6bc0fa401`; the frozen client remains identical to source commit `81d5d5c714c73890efccff172103f65171ecde20`.
The single-file context can now be staged from this checkout. Root callback image build, combined first boot, and actual delivery still require independent integration evidence.
Do not disable checks or duplicate the client to bypass that packaging gate.

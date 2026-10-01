# Foundation Validation Checkpoint

Checked on 2026-10-01. This evidence separates artifact inspection from live startup and compatibility acceptance.

## Verified Artifacts

| Component | Exact artifact | Evidence and remaining checks |
| --- | --- | --- |
| Kirei | Gem `0.10.0`, source commit `ee52ad0860e355dfbf300dca6fc4bb261a6b3e65` | Installed gem checksum matches RubyGems. CLI generated the checked-in scaffold from an empty staging directory. Full dependency lock, Linux build, and application boot remain open. |
| Ruby | `4.0.7-alpine`, index digest in `kirei/bootstrap.lock.json` | Official release and registry manifest verified. Local installed Ruby `4.0.5` generated the scaffold; it does not validate the required Ruby `4.0.7` runtime. |
| Herdr | `0.9.3`, protocol `22`, schema version `1` | Official macOS ARM64 binary checksum matched; `--version` and `api schema --json` passed. Exact schema is in `runtime/contracts/`; Linux and four-CLI handshakes remain open. |
| Mattermost | Team Edition `11.11.1`, index/AMD64 digests in `mattermost/artifact.lock.json` | Registry manifest exposes port `8065`, user `mattermost`, command `/mattermost/bin/mattermost`, and persistent config/data/log paths. Authenticated API/events, restore, and artifact audit remain open. |
| Push proxy | `6.6.0`, index/AMD64 digests in `push-proxy/artifact.lock.json` | Registry and pinned upstream Dockerfile/config sample verified. Dockerfile exposes `8066`, runs as `nobody`, and uses config/cert volumes. Startup/provider/compatibility checks remain open. |
| PostgreSQL | `18.6-alpine`, index digest `sha256:77f585114c32fbca283dc835b0596f4e52b51b4c6662d7810b2f4084f60a1873` | Official registry config identifies version `18.6`, port `5432`, and volume `/var/lib/postgresql`. Initialization and role-isolation checks remain open. |
| Mobile | `release-2.44`, commit `c2fe3beda22befd2178dce431793c09111ed903e` | Official release/ref resolved. Toolchain pins, builds, patch inventory, and server/push compatibility remain open. |

Sources: [Kirei release](https://rubygems.org/gems/kirei/versions/0.10.0), [Ruby release](https://www.ruby-lang.org/en/news/2026/09/15/ruby-4-0-7-released/), [Herdr release](https://github.com/herdrdev/herdr/releases/tag/v0.9.3), [Mattermost release](https://github.com/mattermost/mattermost/releases/tag/v11.11.1), [push proxy Dockerfile](https://github.com/mattermost/mattermost-push-proxy/blob/v6.6.0/docker/Dockerfile), [mobile release](https://github.com/mattermost/mattermost-mobile/releases/tag/release-2.44), and official Docker Hub manifests inspected with `docker buildx imagetools inspect`.

Registry lookup verifies artifact identity, not safety, successful startup, or application compatibility.
Review complete licenses/notices, bundled plugins, dependencies, and outputs before release.

## Local Capability and Checks

- Docker Compose `5.5.1` and registry inspection work without a running Docker daemon.
- Docker Desktop started normally for the live follow-up below. No installation or security permission changes were needed.
- Root Compose currently starts only local PostgreSQL and Mattermost dependencies once Docker is available.
- `docker compose --env-file .env.example config --quiet` passed without starting containers.
- `sh -n scripts/init-postgres.sh` and generated Ruby syntax checks passed.
- The local PostgreSQL initializer creates independent application roles/databases and removes public connection privileges on them.
  Its live follow-up verified both own-database connections and both denied cross-database connections.
- Public sample passwords in `.env.example` are disposable local examples. No production credentials were created or used.

Kirei startup commands, callbacks, listener, worker, Runtime image, and push configuration are component implementation work.
Compose deliberately has no dummy substitutes for those applications.

### Live Follow-up During Foundation Review

Docker Engine `29.8.0` became available after starting the existing Docker Desktop normally.
The isolated `digitaltwin-foundation-check` project used approved public sample configuration, disposable volumes, and random loopback ports.

- PostgreSQL `18.6` initialized and became healthy.
- Kirei and Mattermost roles each connected to their own database.
- Both cross-database connections failed with `permission denied for database` and missing CONNECT privileges.
- Mattermost Team Edition `11.11.1` started under AMD64 emulation on the macOS ARM64 host and became healthy.
- `GET /api/v4/system/ping` returned HTTP 200 with `status: OK` and the expected version header.
- Four real-PostgreSQL migration-helper regressions passed: integer migrate/status, repeated migrate, rollback through zero, invalid steps, and numbered generation.
  These focused tests used local Ruby `4.0.5` with a fixture bootstrap; required Ruby `4.0.7` application boot remains open.
- The migration helper was corrected from the upstream timestamp assumption to the plan's IntegerMigrator/`schema_info.version` convention.

The disposable project and its volumes were removed after checks. Docker remains available for component workers.
No provider sessions, production access, or paid calls were created. Authenticated Mattermost bot/event behavior was not tested by the health check.

## Independent Work and Blocking Gates

Build recipes, dependency selection, upstream configuration, artifact audits, offline tests, and mobile CI preparation can proceed now.
Missing mobile enrollment/signing/device setup does not block server implementation.

Docker now supports local image builds and dependency startup. Full Kirei/Runtime builds and authenticated interface checks remain component work.
The following live evidence still gates dependent implementation under the existing plan:

1. Authenticated Mattermost bot/events, verified sender/thread/membership, and reconnect recovery.
2. Four real CLIs through Linux Herdr, start/prompt/state/stop behavior, and a verified Writer settled handshake.
3. Selected Master CLI's real MCP round trip with source context.
4. The disposable mention → queued dispatch → one CLI → reply in its original thread slice before production Tasks 3–5.

Tasks 6–10 cannot treat schema inspection, successful generation, or simulated fixtures as passing those required checks.
Operator test credentials may be needed for real CLIs; create no credentials or paid sessions without authorization.
Keep signed-device push and production restore/deployment checks separate from local server checks.

## Concrete Worker Briefs

Start each branch/worktree from the reviewed foundation commit. The root session arranges workers and integrates their branches.

| Branch suggestion | Owned files | First deliverable and checks |
| --- | --- | --- |
| `build/kirei` | `kirei/`; coordinate shared contract changes through integrator | Finish Ruby 4.0.7 dependency lock/platforms, Puma/startup and component tests. Validate generated health routes and pending-migration startup. Coordinate Task 1 slice before production jobs/routing/enrollment. |
| `build/runtime` | `runtime/` | Verify Linux Herdr 0.9.3 against captured schema, pin remaining tools/base, build non-root image and tool smoke checks. Prove four-CLI/idle/MCP behavior before dependent session/review work. Kirei owns adapter, sessions schema, and client source. |
| `build/mattermost` | `mattermost/` | Validate pinned Team Edition 11.11.1 bot permissions, authenticated ordinary thread replies, identity/membership, REST backfill and restore. Deliver sanitized fixtures and artifact/license audit. Propose Compose edits through integrator. |
| `build/push-proxy` | `push-proxy/` | Validate 6.6.0 config, health, safe secret references and server/mobile compatibility. Prepare offline checks now; APNs/FCM delivery waits for operator setup. |
| `build/mobile` | `mobile/` | Build reproducibly from the recorded revision, pin toolchains, retain notices, record patches, and run offline checks. Coordinate chat/deep-link/push behavior; signing/device checks remain explicit operator evidence. |
| `test/integration` | root `tests/` after integration; root glue by integrator agreement | Test startup/readiness, independent DB roles, socket/UID/mount contracts, thread routing, callbacks, duplicate handling, review exclusion and recovery. Map final evidence to the unchanged Phase 0 acceptance matrix. |

The integrator owns root Compose/environment, `scripts/`, shared interfaces, and cross-service fixtures.
Docs and scripts do not require standalone application implementation sessions.
Merge dependency-compatible component results before the final integration test worker runs.

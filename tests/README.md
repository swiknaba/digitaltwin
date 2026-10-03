# Automated Integration Tests

Repository-level tests across deployables, owned by the integration test worker after component integration.
Component unit, adapter, and database tests stay in their component folders.
Shared service fixtures and acceptance checks belong here when they exercise multiple deployables.

## Why This Exists

Component tests cannot establish that independently built services work together.
This folder verifies shared contracts and recovery without giving one component ownership of another component's source.

## API and Configuration Contract

Run tests from the repository root against local Compose with disposable data and simulated providers by default.
Run `python3 -m unittest discover -s tests -v` for root Compose agreement checks.
These inspect resolved configuration; they do not build or boot applications.
Run `scripts/acceptance dependencies` for disposable live PostgreSQL/Mattermost dependency checks.
The final integration worker extends this harness after component merges; neither command proves the real provider roundtrip.

Required checks include database-role separation, startup/readiness, shared socket access, verified callbacks, and correct concurrent thread routing.
Cover duplicate events, review dispatch exclusion, crash/restart recovery, and rejected cross-session callbacks.
Map final checks to all 32 existing Phase 0 acceptance criteria; label simulated and live evidence separately.
Mobile push/device, real provider CLI/MCP, encrypted restore, and production checks need their stated operator prerequisites.
Test fixtures must not contain credentials or copied private conversation content.

## Disposable combined suite

After the reviewed backend commit is merged into the test checkout, run:

```sh
DIGITALTWIN_RUN_COMPOSE_TESTS=1 \
  DIGITALTWIN_REVIEWED_BACKEND_REVISION=<exact-reviewed-merged-commit> \
  python3 -m unittest discover -s tests -v
```

The suite verifies that the exact backend revision is an ancestor of HEAD before building.
It uses public `.env.example` samples, ignores ambient Compose/password overrides, builds uniquely tagged images,
and creates random loopback ports and uniquely named containers/networks/volumes.
Cleanup removes only this suite's project volumes and its unique image tags, including on setup/test failure.
It stages only checksum-pinned backend callback/MCP files into the ignored build context.
The credential-free default must exclude the gated listener and push profiles.

Real local checks cover PostgreSQL role ownership and cross-database denials, the current migration version,
Falcon parallel HTTP/request isolation and bounded JSON rejection, UID/mount/capability restrictions,
the shared 0600 Herdr socket, packaged callback hash, chat plugin absence, and process restarts.
Synthetic database fixtures cover job deduplication, lease recovery, stale completion, uncertain effects,
gated dispatch after restart, and callbacks/replays bound to two separate threads.
The callback markers are public synthetic strings with short database expiry and a temporary Runtime `/tmp` file;
the file is removed and fixture sessions invalidated after the test. No provider/chat accounts or login state are created.

JSON evidence identifies the tested Git/backend revisions and explicitly labels authenticated chat,
provider CLI, Master MCP, and full Phase 0 acceptance as untested. Startup failures retain bounded, sanitized logs from the disposable services and captured Compose progress.
Without the explicit opt-in, normal discovery skips the live suite and runs configuration tests only.

| Phase 0 criterion | Scope of this suite; remaining evidence |
| --- | --- |
| 1 | Blocked: published images/production infrastructure |
| 2 | Real local default core boot; authenticated chat and push readiness remain open |
| 3 | Local configuration contracts only; hosted task portability untested |
| 4 | Real local DB/chat/web/worker/Runtime health; listener/push/Headscale/Tailscale open |
| 5-6 | Real local UIDs, mounts, capability and socket restrictions |
| 7 | Container restart and durable job state; full host/login/workspace recovery untested |
| 8-10 | Blocked: four real CLIs, Tailnet attachment and external SSH test |
| 11-16 | Synthetic callback two-thread binding only; Master, role sessions and enrollment acceptance open |
| 17-24 | Blocked: actual approval/review coordination and settled Writer evidence |
| 25-26 | Blocked: verified PR delivery and automatic-merge exclusion |
| 27-28 | Blocked: Master reconstruction and independent peer fleet |
| 29-30 | Blocked: encrypted restore, authenticated ordinary chat, signed mobile push/deep links |
| 31-32 | Blocked: research and pushed configured memory repository |

Client pin/staging validation: `python3 -m unittest discover -s tests -p test_client_contract.py`.
After building the pinned with-callback image, run `tests/fixtures/runtime_clients.rb` via its Ruby
entrypoint with network disabled. It verifies installed stdio MCP and callback HTTP wire behavior
against an in-container fixture; no provider/CLI or authenticated chat compatibility is claimed.

## Final local validation after the backend refactor

`evidence/final-local-e2e.json` records 23 passing root checks on main `1f34bb9d3ac6d6252c646c316b2d7de0ef6bd5b9`
with the fixture/harness changes identified by SHA-256. Six checks boot real disposable containers.
Separate backend `bin/check` passed 243 examples, RuboCop, and the whole-project Sorbet check.
Installed MCP/callback clients passed synthetic HTTP fixtures; real unauthenticated Claude print mode
returned the expected login-required result. Interactive Claude startup on the network-disabled probe
returned to the shell after its connection failure; Herdr's initial readiness response alone does not
prove a settled provider session. No authenticated chat, model response, or live Master MCP is claimed.

Before Docker Desktop was restarted by the operator, even a native arm64 `/bin/true` container
remained `Created` with PID 0. Both initial suites timed out before application execution.
The recovered run passed without increasing timeouts or changing production gates.

For a short human core/CLI check from the repository root:

1. Run `./scripts/dev`, then `docker compose ps`; core services should be healthy.
2. Open `http://localhost:8065` and create your local chat account.
3. Run `docker compose exec agent-runtime claude auth login` and complete your own login.
4. Run `docker compose exec agent-runtime claude --print 'Reply exactly DIGITALTWIN_OK'`; expect that response.

This checks the local UI and direct provider CLI. Commander/chat dispatch remains gated:
the chat listener is opt-in, bot/account wiring is missing, and workflow dispatch policy returns false.
These steps do not validate the complete Commander workflow or authorize a remote deployment.

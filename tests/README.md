# Automated Integration Tests

Repository-level tests across deployables, owned by the integration test worker after component integration.
Component unit, adapter, and database tests stay in their component folders.
Shared service fixtures and acceptance checks belong here when they exercise multiple deployables.

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

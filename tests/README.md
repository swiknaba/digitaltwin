# Automated Integration Tests

Repository-level tests across deployables, owned by the integration test worker after component integration.
Component unit, adapter, and database tests stay in their component folders.
Shared service fixtures and acceptance checks belong here when they exercise multiple deployables.

## API and Configuration Contract

Run tests from the repository root against local Compose with disposable data and simulated providers by default.
The integration worker chooses the lean runner after actual application contracts exist and documents its exact command here.
No test runner or successful service integration is claimed by this scaffold.

Required checks include database-role separation, startup/readiness, shared socket access, verified callbacks, and correct concurrent thread routing.
Cover duplicate events, review dispatch exclusion, crash/restart recovery, and rejected cross-session callbacks.
Map final checks to all 32 existing Phase 0 acceptance criteria; label simulated and live evidence separately.
Mobile push/device, real provider CLI/MCP, encrypted restore, and production checks need their stated operator prerequisites.
Test fixtures must not contain credentials or copied private conversation content.

# Digitaltwin

A self-hosted remote AI team that can interview its owner, build code and research artifacts, keep durable knowledge, and collaborate with another independently operated team.

## Docs

- [Repository layout and parallel build](docs/repository-layout-and-parallel-build.md)
- [Shared service boundaries and validation gates](docs/interfaces/service-boundaries.md)
- [Local integration wiring and early real roundtrip](docs/interfaces/local-integration.md)
- [Phase 0: agent fleet specification](docs/agent-fleet-architecture-and-review.md)
- [Phase 0: implementation plan](docs/superpowers/plans/2026-09-30-digitaltwin-phase-0.md)
- [Phase 1: group calls and AI voice](docs/phase-1-voice-controller.md)

The Digitaltwin runtime image uses [Wagglebot](https://github.com/swiknaba/wagglebot) for agent instructions, skills, MCP settings, and project memory.

The plan uses the official, unmodified [Mattermost Team Edition](https://github.com/mattermost/mattermost) server with external Kirei Master/Worker bots. Native channels and threads replace the planned Campfire fork. Worker replies retain Kirei's durable outbox and session-bound routing.

We maintain our own Apache 2.0 mobile builds and host the existing Mattermost push proxy with APNs/FCM. Application IDs, signing, distribution, and updates require future human setup and maintenance. Phase 1 independently integrates self-hosted LiveKit for group calls and AI voice. [LiteLLM/MCP](https://github.com/swiknaba/digitaltwin/issues/4) remains a direction after Phase 2, outside the chat layer.

Audit exact server artifacts, mobile builds, dependencies, and notices before release. The official compiled Team Edition license differs from source-build licensing. Commercially licensed components, Calls/rtcd, and the Agents plugin are excluded from the required stack; needed replacements are independent implementations.

This repository provides application images and local development Compose. The infrastructure repository or hosting platform supplies production services and orchestration.

## Implementation Scaffold

Component contracts live in [integration-backend/](integration-backend/README.md), [agent-runtime/](agent-runtime/README.md), [chat-backend/](chat-backend/README.md), [push-service/](push-service/README.md), and [mobile-apps/](mobile-apps/README.md).
Repository automation belongs in [scripts/](scripts/README.md); cross-service automated integration tests belong in [tests/](tests/README.md).

The scaffold includes generated Kirei files, verified upstream artifact identities, and local PostgreSQL/Mattermost dependency Compose.
See the [foundation validation checkpoint](docs/interfaces/foundation-validation.md) for exact versions, checks, worker briefs, and remaining gates.
Application process startup and live integration are not yet verified.
Task 1's live compatibility slice remains a prerequisite for dependent implementation.

Validate local dependency configuration with `docker compose --env-file .env.example config --quiet`.
Run `scripts/acceptance config` for both dependency and prepared backend Compose contracts.
Run `scripts/acceptance dependencies` for disposable live dependency checks using public samples.
Copy `.env.example` to ignored `.env` before local startup. Docker must be running.
The database initialization script runs only on a new local PostgreSQL volume; changing `.env` does not rotate existing roles.

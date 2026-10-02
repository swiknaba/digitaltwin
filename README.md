# Digitaltwin

A self-hosted remote AI team that can interview its owner, build code and research artifacts, keep durable knowledge, and collaborate with another independently operated team.

## Why This Exists

One repository versions the components and their shared integration agreement together.
Root files wire local development; each component folder owns its implementation and build inputs.

## Docs

- [Repository layout and parallel build](docs/repository-layout-and-parallel-build.md)
- [Shared service boundaries and validation gates](docs/interfaces/service-boundaries.md)
- [Local integration wiring and early real roundtrip](docs/interfaces/local-integration.md)
- [Phase 0: agent fleet specification](docs/agent-fleet-architecture-and-review.md)
- [Phase 0: implementation plan](docs/superpowers/plans/2026-09-30-digitaltwin-phase-0.md)
- [Phase 1: group calls and AI voice](docs/phase-1-voice-controller.md)

The Digitaltwin runtime image uses [Wagglebot](https://github.com/swiknaba/wagglebot) for agent instructions, skills, MCP settings, and project memory.

The plan uses the official compiled [Mattermost Team Edition](https://github.com/mattermost/mattermost) core with external Kirei Master/Worker bots. Minimal derived packaging removes excluded plugin archives while preserving the core and notices. Native channels and threads replace the planned Campfire fork. Worker replies retain Kirei's durable outbox and session-bound routing.

We maintain our own Apache 2.0 mobile builds and host the existing Mattermost push proxy with APNs/FCM. Application IDs, signing, distribution, and updates require future human setup and maintenance. Phase 1 independently integrates self-hosted LiveKit for group calls and AI voice. [LiteLLM/MCP](https://github.com/swiknaba/digitaltwin/issues/4) remains a direction after Phase 2, outside the chat layer.

Audit exact server artifacts, mobile builds, dependencies, and notices before release. The official compiled Team Edition license differs from source-build licensing. Commercially licensed components, Calls/rtcd, and the Agents plugin are excluded from the required stack; needed replacements are independent implementations.

This repository provides application images and local development Compose. The infrastructure repository or hosting platform supplies production services and orchestration.

## Implementation Scaffold

Component contracts live in [integration-backend/](integration-backend/README.md), [agent-runtime/](agent-runtime/README.md), [chat-backend/](chat-backend/README.md), [push-service/](push-service/README.md), and [mobile-apps/](mobile-apps/README.md).
Repository automation belongs in [scripts/](scripts/README.md); cross-service automated integration tests belong in [tests/](tests/README.md).

The repository includes the reviewed backend, Runtime, derived chat packaging, push/mobile preparation, and local core Compose.
See the [foundation validation checkpoint](docs/interfaces/foundation-validation.md) for exact versions, checks, worker briefs, and remaining gates.
Independent local integration verified core startup, migrations, health, private socket access, synthetic callbacks, and restart/durable-job behavior.
Authenticated chat, real provider CLI/MCP, signed mobile delivery, and full Phase 0 acceptance remain open.
Task 1's real chat-to-provider slice remains a prerequisite for dependent workflow implementation.

Validate local dependency configuration with `docker compose --env-file .env.example config --quiet`.
Run `scripts/acceptance config` for Compose contracts.
Run `scripts/acceptance dependencies` for disposable live dependency checks using public samples.
Build the reviewed local chat first with `docker compose --env-file .env.example build mattermost`.
With Docker running, use `scripts/dev` for local boot. It creates ignored `.env` from public samples only if absent,
stages the checksum-verified callback file, then runs `docker compose up --build -d --wait`.
The default starts PostgreSQL, plugin-free chat, backend web/worker, and Runtime after volume setup and successful migrations.
The equivalent manual setup is `cp .env.example .env`, `scripts/prepare-callback-context`, then `docker compose up --build -d --wait`.
Preserve an existing `.env`. The public passwords are local development samples; use this stack only for local development.
The authenticated listener (`chat-validation`) and push (`push`) remain opt-in; their operator credentials and mappings require separate setup.
Worker validation is disabled; unimplemented provider/workflow effects stay blocked. Local health does not mean those features are accepted.
Stop containers with `docker compose down`; retain volumes for the next boot. Use `down --volumes` only to discard disposable data.
The database initialization script runs only on a new local PostgreSQL volume; changing `.env` does not rotate existing roles.

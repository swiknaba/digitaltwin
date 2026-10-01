# Digitaltwin

A self-hosted remote AI team that can interview its owner, build code and research artifacts, keep durable knowledge, and collaborate with another independently operated team.

## Docs

- [Phase 0: agent fleet specification](docs/agent-fleet-architecture-and-review.md)
- [Phase 0: implementation plan](docs/superpowers/plans/2026-09-30-digitaltwin-phase-0.md)
- [Phase 1: voice conversation with the controller](docs/phase-1-voice-controller.md)

The Digitaltwin runtime image uses [Wagglebot](https://github.com/swiknaba/wagglebot) for agent instructions, skills, MCP settings, and project memory.

The plan includes a maintained [Campfire Rails fork](https://github.com/basecamp/once-campfire) under `apps/campfire/`. It uses the same PostgreSQL server with a separate database and role. A Campfire-associated Redis sidecar supplies jobs, live messaging, caching, and Kredis. Worker replies use Kirei's durable outbox with session-bound thread routing.

This repository provides application images and local development Compose. The infrastructure repository or hosting platform supplies production services and orchestration.

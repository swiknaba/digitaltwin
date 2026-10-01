# Digitaltwin

A self-hosted remote AI team that can interview its owner, build code and research artifacts, keep durable knowledge, and collaborate with another independently operated team.

## Docs

- [Phase 0: agent fleet specification](docs/agent-fleet-architecture-and-review.md)
- [Phase 0: implementation plan](docs/superpowers/plans/2026-09-30-digitaltwin-phase-0.md)
- [Phase 1: group calls and AI voice](docs/phase-1-voice-controller.md)

The Digitaltwin runtime image uses [Wagglebot](https://github.com/swiknaba/wagglebot) for agent instructions, skills, MCP settings, and project memory.

The plan uses the official, unmodified [Mattermost Team Edition](https://github.com/mattermost/mattermost) server with external Kirei Master/Worker bots. Native channels and threads replace the planned Campfire fork. Worker replies retain Kirei's durable outbox and session-bound routing.

We maintain our own Apache 2.0 mobile builds and host the existing Mattermost push proxy with APNs/FCM. Application IDs, signing, distribution, and updates require future human setup and maintenance. Phase 1 independently integrates self-hosted LiveKit for group calls and AI voice. [LiteLLM/MCP](https://github.com/swiknaba/digitaltwin/issues/4) remains a direction after Phase 2, outside the chat layer.

Audit exact server artifacts, mobile builds, dependencies, and notices before release. The official compiled Team Edition license differs from source-build licensing. Commercially licensed components, Calls/rtcd, and the Agents plugin are excluded from the required stack; needed replacements are independent implementations.

This repository provides application images and local development Compose. The infrastructure repository or hosting platform supplies production services and orchestration.

# Repository Layout and Parallel Build

Use one top-level folder per deployable or independently released client.
Name folders by responsibility so implementation technology can change without another layout migration.
Keep documentation in `docs/` and non-deployable automation in `scripts/`.
This scaffold refines the merged Phase 0 plan and prepares component implementation.

## Target Layout

The component folders contain contract READMEs and verified artifact records.
Kirei includes its generated scaffold; root Compose configures local upstream dependencies. Application builds and live validation remain pending.

```text
digitaltwin/
├── integration-backend/# Ruby control plane: web, worker, event listener; one image
├── agent-runtime/      # Herdr, four agent CLIs, Wagglebot, tools; one image
├── chat-backend/       # Official Team Edition artifact pins and configuration
├── push-service/       # Existing upstream push artifact pins and configuration
├── mobile-apps/        # Our iOS/Android build recipe, patches, tests, release pipeline
├── commander/          # Planned persistent Commander instructions and global memory
├── docs/               # Specs, plans, interfaces, operations, acceptance evidence
├── scripts/            # Local setup, integration checks, infrastructure handoff helpers
├── tests/              # Automated integration tests across deployables
├── .agents/            # Repository agent instructions/history
├── compose.yml         # Local development and integration orchestration
├── .env.example        # Local variable names and safe examples
├── .gitignore
├── AGENTS.md           # When repository-specific instructions are needed
├── README.md
└── CHANGELOG.md        # When implementation produces deliverable changes
```

| Folder | Ownership and boundary |
| --- | --- |
| `integration-backend/` | Owns Ruby source, Gemfile/lockfile, Ruby pin, migrations, tests, Dockerfile, and process entry points. Web/worker/listener share this codebase. |
| `agent-runtime/` | Owns Dockerfile, entrypoint, exact tool manifest, Node pin, provisioning, and executable Runtime smoke checks. Herdr remains upstream. |
| `chat-backend/` | Records the official unmodified Team Edition release/digest, configuration examples, and upgrade checks. No server source fork or copied repository. |
| `push-service/` | Records upstream artifact pins, non-secret configuration, and compatibility checks. Push remains separate from Kirei. |
| `mobile-apps/` | Owns reproducible builds from pinned Apache 2.0 upstream source, necessary patches, notices, and signing/distribution references. |
| `docs/` | Owns shared service contracts and sanitized evidence. Preserve the existing spec, Phase 1 document, and Superpowers paths. |
| `scripts/` | Owns commands that run and exit: local database setup, acceptance orchestration, and infrastructure handoff helpers. |
| `tests/` | Owns automated integration tests across deployables; component unit/adapter tests stay inside their folders. |

Two application images are built here: Kirei and Runtime.
Mattermost and push proxy consume upstream artifacts; their workstreams configure and validate those services.
Do not create separate Commander, Worker bot, scheduler, push gateway, or chat application codebases.
Kirei's worker process and the Herdr Runtime are distinct responsibilities.

Keep application commands inside their folders, such as `integration-backend/bin/worker` and `agent-runtime/bin/runtime-smoke`.
Put repository-wide checks in `scripts/`, such as `scripts/acceptance`.
Each build owns its lockfiles and Docker ignore rules; no root workspace package manager is required.
Document the Docker build context explicitly, including Kirei callback/MCP clients included in Runtime without duplicate source ownership.

Fetch pinned mobile source during its reproducible build, and keep our patches and build configuration here.
Do not vendor complete third-party repositories merely to fill the layout.
iOS and Android share `mobile-apps/`; separate internal platform folders only when their build files require them.
Signing, Apple/Google enrollment, APNs/FCM credentials, distribution, and updates need operator ownership and future human setup.

## Infrastructure and Phase Boundaries

Local Compose may start PostgreSQL and other required integration dependencies from upstream images.
PostgreSQL has separate Kirei and Mattermost databases, roles, secrets, and migration ownership.
Headscale, Tailscale networking, S3, DNS, TLS, production orchestration, and backup schedules remain infrastructure responsibilities.
They need no new application folders here.
Keep production configuration and secret values in the infrastructure repository or hosting platform.
An infrastructure helper in `scripts/` documents or prepares a handoff; it does not transfer production ownership here.

Phase 1 adds independent LiveKit integration, voice workers, and client call UI.
Choose their folders when that integration's deployables are specified; create no Phase 0 voice scaffolding.
Phase 0 mobile chat and push are included. Native voice/background call behavior belongs to Phase 1.
Calls/rtcd and the Agents plugin remain excluded. LiteLLM/MCP remains after Phase 2.

## Mapping from the Merged Plan

The generated scaffold follows this layout. Use these targets for remaining planned files.
The Phase 0 plan uses these mappings for implementation.

| Previous planned path | Target path |
| --- | --- |
| Root Kirei `app.rb`, `config.ru`, `app/`, `db/`, `lib/`, `sorbet/`, `spec/`, `Rakefile`, `.irbrc` | Same names under `integration-backend/` |
| `Gemfile`, `Gemfile.lock`, `.ruby-version`, Kirei test setup | `integration-backend/` |
| `config/deployment.example.yml` and other Kirei configuration | `integration-backend/config/` |
| `config/runtime-tools.lock.yml` | `agent-runtime/tools.lock.yml` |
| `.nvmrc` | `agent-runtime/.nvmrc`; mobile owns its independently pinned build toolchain |
| `docker/app.Dockerfile` | `integration-backend/Dockerfile` |
| `docker/runtime.Dockerfile`, `config/runtime-entrypoint.sh` | `agent-runtime/Dockerfile`, `agent-runtime/entrypoint.sh` |
| `bin/{web,worker,chat-listener,digitaltwin,mcp}` | `integration-backend/bin/`; Runtime packages the needed clients from this source |
| `bin/runtime-smoke`, `bin/acceptance` | `agent-runtime/bin/runtime-smoke`, `scripts/acceptance` |
| `apps/mobile/` | `mobile-apps/` |
| Cross-service `spec/integration/` acceptance and image checks | `tests/`; Kirei-only integration tests stay in `integration-backend/spec/integration/` |
| `docs/`, root Compose/environment/repository metadata | Unchanged |

Run host-side Ruby commands from `integration-backend/`; run `docker compose` from the repository root.
Container paths are image contracts, independent of these source paths.
Runtime project workspace roots remain `/workspace/repos` and `/workspace/worktrees/<workflow-uuid>`.
The Commander plan adds a persistent `commander/` scaffold mounted at `/workspace/commander`, with optional Git sync.

## Parallel Work Plan

One Codex session per deployable is a good default after a small shared foundation.
Use a separate branch and Git worktree for each session, with one integration owner.
Folders reduce conflicts; they do not remove shared contracts or prerequisite work.

1. **Validate the boundary first (Task 1).** Agree on verified Mattermost events, Herdr operations, CLI startup/idle behavior, and Commander MCP round trips.
   Record exact pins and sanitized fixtures; prove the disposable mention → Herdr → reply slice before production workflow work.
2. **Establish the foundation (Tasks 2-3).** Bootstrap Kirei, local Compose, separate databases, shared types, durable jobs, inbox, and outbox.
   Agree on start commands, health checks, ENV/secret names, UID/GID, volumes, socket access, and callback authentication/routing.
3. **Run the following streams concurrently once their prerequisites pass.** Each session owns its folder and proposes shared-file changes through the integrator.
4. **Integrate and prove delivery (Tasks 11-13).** Reconcile recovery, finish operations contracts, and run end-to-end acceptance with explicit evidence gaps.

| Workstream | Scope and dependencies |
| --- | --- |
| Integration backend (Kirei) | Tasks 4-5 routing/enrollment, then Tasks 7-10 gates, reviews, Commander, and delivery. Runtime/session contracts and Task 3 state must precede their consumers. |
| Agent runtime (Herdr) | Task 6 image, tools, persistence, and provisioning after Task 1 validation. Coordinate Kirei's Herdr adapter, sessions migration, and packaged clients with the Kirei owner. |
| Chat backend + push service | Configure pinned upstream services, verify authenticated threads/reconnect and push compatibility, and document upgrades/restore. One session can own both small configuration folders. |
| Mobile apps | Build pipeline, patches, chat/deep links, and push checks against the agreed server/push versions. Device, signing, and distribution checks need operator setup. |
| Integration | Own root Compose/environment glue, cross-service startup, smoke checks, production handoff, and acceptance evidence. Merge compatible changes in dependency order. |

Do not split Kirei web, worker, listener, and Commander into separate deployable sessions.
They share one Ruby application, schema, dependencies, and transaction rules.
Additional Kirei domain sessions can follow later with explicit file ownership and stable shared types.
Task 1 validation gates still block Tasks 6-10 when required contracts lack evidence.
Task 3 shared types precede Tasks 4-6; review coordination follows verified routing, sessions, and workflow gates.

The integration owner controls root files, `tests/`, cross-service version compatibility, shared fixtures, and `docs/interfaces/` contracts.
Component owners control their dependency lockfiles; the integrator reviews changes that affect another component.
The Kirei owner controls migration numbers and shared entities; consumers request changes rather than adding competing schemas.
Version external callback and peer envelopes only where compatibility requires it; keep Kirei domain types in Kirei.
No shared library or schema service is needed initially.

Before merging each stream, verify its component checks and relevant cross-service contract checks.
Then verify Compose configuration, image startup/health, private worker socket access, and correct thread-bound replies.
Final acceptance includes concurrent threads, review exclusion, restart recovery, mobile push/deep links, and the existing acceptance matrix.
Record simulated, live, and operator-dependent evidence separately; missing credentials or device checks remain open.

The main objection to immediate parallel builds is interface drift, especially Runtime callbacks and mobile, server, and push compatibility.
The short foundation and one integration owner address that risk without adding a framework or deeper directory hierarchy.

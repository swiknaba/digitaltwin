# AgentsView Usage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Provide scoped Runtime token and cost reports through SSH and Commander without exposing transcripts or arbitrary commands.

**Architecture:** Package the pinned AgentsView binary only after its Alpine compatibility probe passes. Use its native usage/activity reports and one backend-owned stdio MCP adapter to enforce the shared range, timezone, source, and cost-status contract.

**Tech Stack:** Alpine Linux AMD64, AgentsView v0.44.0, Python 3 standard library, Ruby 3.4/Sorbet standalone MCP client, Docker.

**Spec:** `docs/superpowers/specs/2026-10-04-agentsview-usage-design.md`

## Global Constraints

- Start from the exact resolved `origin/main` head and use an isolated worktree.
- Download and execute AgentsView only under the recorded 2026-10-04 action-time approval; repeat verification in the disposable Runtime image.
- Pin `v0.44.0` and verify SHA-256 `037ea7a46d52e06b20363b4aa7cd7f28e32f31d8215803d6e9a0c96bac5818e3`.
- The pinned archive has been verified to require glibc: it runs in Debian Bookworm but fails before startup in Alpine 3.23. Do not implement the Dockerfile task until the user reviews and selects a musl-compatible artifact/build or a Runtime-base change.
- Read only the four declared Runtime session roots and synthetic fixtures in tests.
- Default `RUNTIME_USAGE_TIMEZONE` to `UTC`; validate operator-supplied IANA timezones.
- Expose no arbitrary command, session-content, remote-sync, credential, UI, or public-network capability.
- Treat `unknown`/unavailable cost differently from a reported zero.

## Review Focus

1. A malformed range or timezone must fail before spawning AgentsView.
2. A provider path outside the four allowed Runtime roots must never be scanned.
3. Exact-hour requests must fail explicitly rather than returning incomplete token totals.
4. An unpriced or unsupported record must not appear as a valid zero cost.
5. Commander must not discover transcript-reading tools or pass shell arguments.

---

### Task 1: Pin and prove the Runtime dependency

**Files:**
- Modify: `agent-runtime/Dockerfile`
- Modify: `agent-runtime/tools.lock.yml`
- Modify: `agent-runtime/bin/runtime-smoke`
- Modify: `agent-runtime/bin/test-image`
- Create: `agent-runtime/bin/agentsview-fixture.py`

**Interfaces:**
- Produces: `/usr/local/bin/agentsview` at the pinned version.
- Produces: `RUNTIME_USAGE_TIMEZONE`, `AGENTSVIEW_DATA_DIR`, and four explicit session-root configuration values.

- [ ] **Step 1: Add synthetic fixture assertions**

Write fixtures for the four roots, no usable-token data, and a reported-zero cost. Assert no fixture contains a real home path or prompt.

- [ ] **Step 2: Run the fixture check before installation**

Run: `python3 agent-runtime/bin/agentsview-fixture.py --self-test`

Expected: PASS without AgentsView installed.

- [ ] **Step 3: Add the checksum-pinned download and configuration**

Download the approved Linux AMD64 archive in the Dockerfile, verify its SHA-256 before extraction, and set only the declared roots/data directory. Record release URL, revision, checksum, license, and provenance/SBOM URLs in `tools.lock.yml`.

- [ ] **Step 4: Add disposable image assertions**

Run `agentsview --version`, an offline synthetic sync, and JSON calendar report checks. Assert no listener or published Runtime port exists.

- [ ] **Step 5: Verify the component image**

Run: `docker build --platform linux/amd64 -t digitaltwin-runtime-agentsview:local agent-runtime && agent-runtime/bin/test-image digitaltwin-runtime-agentsview:local`

Expected: PASS, or stop with documented Alpine incompatibility.

### Task 2: Add the one-tool Commander adapter

**Files:**
- Create: `integration-backend/app/adapters/mcp/agentsview_usage_server.rb`
- Create: `integration-backend/app/adapters/mcp/agentsview_usage_command.rb`
- Create: `integration-backend/app/adapters/mcp/agentsview_usage_response.rb`
- Modify: `integration-backend/bin/mcp`
- Modify: `agent-runtime/contracts/kirei-clients.json`
- Modify: `scripts/prepare-callback-context`
- Modify: `agent-runtime/Dockerfile`
- Test: `integration-backend/spec/adapters/mcp/agentsview_usage_server_spec.rb`
- Test: `tests/test_client_contract.py`

**Interfaces:**
- Consumes: `get_usage(range:, agent: nil)` only, with the range variants defined by the spec.
- Produces: normalized range boundaries, token totals, cost status, pricing freshness, source machine, and explicit failures.

- [ ] **Step 1: Write failing adapter contract tests**

Cover every calendar range form, invalid timezone/range/agent, rejection of exact-hour requests, reported zero, estimated cost, partial estimates with unpriced rows, unavailable cost, and rejection of unknown fields.

- [ ] **Step 2: Run the focused tests to verify failure**

Run: `cd integration-backend && bundle exec rspec spec/adapters/mcp/agentsview_usage_server_spec.rb`

Expected: FAIL because the standalone adapter is absent.

- [ ] **Step 3: Implement strict standalone adapter files**

Use `# typed: strict`, fixed executable and argument construction, process timeouts, stdout JSON parsing, and typed failure results. Do not load the Kirei application or add a generic command tool.

- [ ] **Step 4: Package and checksum the adapter**

Extend the existing client manifest/staging process. Verify the Runtime receives exactly the checksum-pinned standalone files.

- [ ] **Step 5: Run focused adapter and package tests**

Run: `cd integration-backend && bundle exec rspec spec/adapters/mcp/agentsview_usage_server_spec.rb && cd .. && python3 tests/test_client_contract.py`

Expected: PASS with synthetic AgentsView output only.

### Task 3: Document controlled operation and UI boundary

**Files:**
- Modify: `agent-runtime/README.md`
- Modify: `docs/interfaces/master-routing-setup.md`
- Create: `agent-runtime/evidence/agentsview-usage-fixture.md`

**Interfaces:**
- Produces: SSH examples for every supported range and Commander MCP setup for the one usage tool.

- [ ] **Step 1: Document range and cost semantics**

Show `today`, month-to-date, last N days, and custom-date examples. State inclusive calendar dates, the explicit exact-hour limitation, timezone source, stale-archive behavior, and reported/estimated/unavailable costs.

- [ ] **Step 2: Document private UI as disabled-by-default**

Show loopback foreground serving and SSH forwarding only. State Tailnet binding requires explicit infrastructure authentication review. Do not add a Compose service or port mapping.

- [ ] **Step 3: Record synthetic evidence and run documentation checks**

Run: `git diff --check && docker compose --env-file .env.example config --quiet`

Expected: PASS; no service gains an AgentsView UI port.

### Task 4: Whole-branch verification and review

**Files:**
- Test: `agent-runtime/bin/test-image`
- Test: `tests/test_client_contract.py`
- Test: `integration-backend/spec/adapters/mcp/agentsview_usage_server_spec.rb`

- [ ] **Step 1: Run exact-head checks**

Run the Runtime image test, focused backend adapter test, client-contract test, `bundle exec spoom srb tc`, RuboCop, and Compose config on the final commit.

- [ ] **Step 2: Perform independent review**

Review the complete branch diff for source isolation, cost-state correctness, timezone boundaries, process argument control, and default network exposure.

- [ ] **Step 3: Prepare a draft PR based on `origin/main`**

Include the exact release evidence, synthetic test output, unresolved live MCP/SSH gates, and no deployment claim.

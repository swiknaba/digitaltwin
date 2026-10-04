# AgentsView Runtime Usage Design

## Goal

Add local token-usage reporting to the Runtime. Support safe SSH and Commander queries for explicit time ranges.

## Scope

- Package one pinned AgentsView release in the Runtime image.
- Read only the Runtime user's configured CLI session roots.
- Report token totals and cost provenance through SSH CLI and one read-only Commander MCP tool.
- Keep the UI disabled by default.

This feature does not add billing, credentials, remote synchronization, public networking, or cross-fleet aggregation.

## User-visible contract

`get_usage` accepts an optional agent and exactly one range:

| Range | Semantics |
| --- | --- |
| `today` | Current local calendar day. |
| `current_month` | Month-to-date, from the first local day through today. |
| `last_days: N` | N complete calendar days ending today, where `1 <= N <= 90`. |
| `dates: {from, to}` | Inclusive ISO local dates, where `from <= to`. |

The configured `RUNTIME_USAGE_TIMEZONE` must be an IANA timezone. It defaults to `UTC` in shared image configuration. An operator can set it to `Europe/Berlin` for the requesting fleet.

Calendar ranges use inclusive date boundaries in that timezone. The response includes the resolved timezone, boundaries, archive freshness, agent filter, and source machine. Exact-hour ranges are rejected in this release because upstream usage reports aggregate the complete token classes by day; its activity command does not provide an equivalent complete token breakdown.

The response includes input, output, cache-creation, and cache-read tokens. It returns a cost object with one of these states:

- `reported`: an upstream session reported the amount, including a valid zero.
- `estimated_api`: AgentsView priced logged tokens from its price catalog.
- `mixed`: the selected rows contain both reported and estimated amounts.
- `partial_estimate`: one or more token rows are unpriced, so the amount covers priced rows only.
- `unavailable`: source logs lack usable token data or no trustworthy cost classification exists.

`unavailable` is never serialized as zero. The result never claims a subscription invoice or invents subscription charges.

## Architecture

AgentsView remains the parser, archive, and calculator. The Runtime uses the pinned `agentsview` binary with `AGENTSVIEW_DATA_DIR=/home/runtime/.agentsview` and only these roots:

- Codex: `/home/runtime/.codex/sessions`
- Claude Code: `/home/runtime/.claude/projects`
- Gemini: `/home/runtime/.gemini`
- OpenCode: `/home/runtime/.local/share/opencode`

The SSH command invokes upstream `agentsview sync` and `agentsview usage daily --json --timezone <configured>` for calendar ranges. It reads only those declared roots but creates a local archive in the persistent Runtime home.

Upstream `agentsview mcp` is not registered directly with Commander. Its `get_usage_summary` tool accepts only dates and defaults to UTC, while the same server also exposes transcript/content tools. The existing `digitaltwin-mcp` stdio server dynamically retrieves Kirei's tool definitions from `/internal/master/manifest` and forwards calls to `/internal/master/tools`; it has no external-MCP allowlist/proxy feature. A small typed local `get_usage` gateway therefore reuses that server's JSON-RPC protocol and checksum-packaging path, but adds only one fixed tool rather than a second protocol or the upstream server's discovery surface. It validates the range and agent enum, starts no arbitrary command, invokes only the fixed AgentsView commands, and returns the normalized result.

The optional UI is not a Compose service. Operators may run it manually on loopback and use SSH forwarding. Any Tailnet binding needs explicit bearer authentication and infrastructure review. No UI port is published by default.

## Safety and privacy

Session roots and the AgentsView archive can contain prompts, responses, tool output, paths, and project names. Tests use synthetic roots only. The Runtime does not read host homes, upload raw archives, configure remote sync, or create credentials. Pricing refreshes are disabled for deterministic offline tests; operational use must label stale pricing data.

## Compatibility and release control

The candidate release is AgentsView `v0.44.0`, Linux AMD64 archive SHA-256 `037ea7a46d52e06b20363b4aa7cd7f28e32f31d8215803d6e9a0c96bac5818e3`. The verified artifact runs `--version` and `--help` in disposable Debian Bookworm, but fails before startup in disposable Alpine 3.23 because it requests glibc's `/lib64/ld-linux-x86-64.so.2`. The Runtime uses Alpine/musl, so this release cannot be installed there as-is. A compatibility failure blocks release; it does not add an unreviewed libc shim or sidecar. The subsequent design decision must choose a provenance-reviewed musl-compatible upstream artifact, a reviewed reproducible musl build, or a Runtime base-image change.

The one user-approved macOS aggregate validation used the local archive after `sync` without `--host`, then queried with `--agent codex`. It therefore proves neither all harnesses nor fleet-wide usage: the filter intentionally excludes non-Codex rows, and upstream can fan out to configured `remote_hosts` when no host is supplied. Private configuration was not inspected. Production Runtime configuration remains limited to the four declared roots and must use explicit local-only sync settings.

## Acceptance evidence

- Verify the pinned archive checksum, license, provenance/SBOM artifacts, and executable version.
- Run against synthetic Codex, Claude, Gemini, and OpenCode fixtures only.
- Verify calendar boundaries across a Europe/Berlin daylight-saving transition.
- Verify exact-hour requests fail explicitly rather than returning incomplete token data.
- Verify reported zero, estimated amount, and unavailable cost remain distinct.
- Verify malformed ranges, unsupported agents, missing roots, and stale archive failures are explicit.
- Verify the Commander adapter exposes one usage tool and cannot retrieve transcripts or execute caller-provided commands.
- Verify the default Runtime image has no UI listener or published port.

## Open gates

The user must approve execution of the pinned third-party archive in an isolated image build. The existing selected Commander MCP round-trip and private SSH evidence remain separate operational gates.

# AgentsView usage fixture evidence

Recorded 2026-10-06 from the local `linux/amd64` Runtime component image.

- Pinned release: `v0.44.0`, commit `413a87f7bfbd67b2815b1119ac51abc1efbeeaba`.
- Archive SHA-256: `037ea7a46d52e06b20363b4aa7cd7f28e32f31d8215803d6e9a0c96bac5818e3`.
- The image build verified the archive, release provenance JSON, and SPDX JSON
  checksums before extracting `/usr/local/bin/agentsview`.
- `agentsview --version` reported `agentsview v0.44.0` with the pinned commit.
- `agent-runtime/bin/agentsview-fixture.py --self-test` passed. Its disposable
  Claude-shaped record has synthetic token counts plus transcript- and
  credential-like sentinels; the other three roots remain empty fixtures.
- `agent-runtime/bin/test-image digitaltwin-runtime-agentsview:local` passed.
  It ran `agentsview sync` and `usage daily --json --offline --no-sync
  --breakdown --timezone UTC --since 2026-10-04 --until 2026-10-05` in a
  temporary home. The JSON had schema version 6 and included the fixture token
  counts. It also searched both the usage response and generated archive for
  both sentinels and found neither.
- The test verifies `archive_content = "usage"`, the four configured providers,
  no remote-host or UI configuration, no published Runtime port, dropped
  capabilities, and a network-isolated container. It also writes a synthetic
  `remote_hosts` setting, restarts the container, and confirms Runtime replaces
  it with the managed local-only configuration.

The callback-target build separately verified all eight pinned backend client
files. Its network-isolated stdio `tools/list` response contained exactly `get_usage` for the
AgentsView MCP process.

## Open operator gates

- A real private Runtime usage report may be checked only by the operator; this
  fixture run intentionally did not read existing provider state.
- An authenticated Hermes MCP tool call, private SSH transport, and optional
  loopback UI tunnel remain operator/infrastructure checks.
- No UI, public listener, deployment, or provider login is enabled by this
  evidence.

# Independent local integration evidence

No publication, production access, provider login, paid call, chat account creation, signing, or mobile-device test occurred.

## Default entry point verified: frozen head ae71773

Exact tested head: `ae71773036126133b75359fe2673ca0bbb1fbf32`.
Independent diff review found no additional material issue in the promotion.
The former overlays now contain only `services: {}`; default `compose.yml` owns the complete core graph.

The same opt-in unittest command below passed **21 tests** (six integration plus 15 configuration checks), exit 0,
in 42.953 seconds, against this exact head. Fresh migrations, boot, restarts, fixture callbacks/jobs and pool checks passed.
Sanitized result and exact image IDs: `evidence/default-compose.json`.

The unmodified default entry point was separately executed twice:

```sh
COMPOSE_PROJECT_NAME=digitaltwin-dev-check-553be8905907 BACKEND_PORT=0 scripts/dev --wait-timeout 180
```

Each invocation used that same disposable project, with no Compose override or entrypoint shim.
Default chat loopback port8065 was verified unused before startup; backend used a random Docker port.
First run started from absent `.env` in this isolated worktree and copied public samples with mode0600.
A preservation comment was appended to `.env`; its SHA256 stayed identical after the second run.
A synthetic marker row in PostgreSQL and marker files in Runtime `/home/runtime` and `/workspace` survived rerun.
Exactly PostgreSQL/chat/web/worker/Runtime were running and healthy; listener and push stayed excluded.
The test-created `.env` and only this project's containers/volumes/network were removed afterward.
Normal local image caches were retained. No other worker resources were removed.
Sanitized entrypoint result: `evidence/dev-entrypoint.json`.

This proves the plain default core and safe quickstart rerun locally; authenticated/provider/device gates below remain open.

## Prior combined-overlay result: 20 checks pass

```sh
DIGITALTWIN_RUN_COMPOSE_TESTS=1 \
  DIGITALTWIN_REVIEWED_BACKEND_REVISION=b45cf0aa827dd19c81e9791c7b5e82ef8d0e36d0 \
  python3 -m unittest discover -s tests -v
```

Exit 0: six actual combined integration tests and 14 root configuration tests pass, in 42.585 seconds.
The actual Rake migration entry point completes all six migrations from a fresh database without fixture preloading.
Default startup excludes the credential-gated listener and push profiles; worker dispatch remains closed.

Real container checks pass: own/cross-database roles, health/JSON, 30 concurrent Falcon requests with distinct request IDs,
bounded malformed/oversized JSON rejection, non-root UIDs, private mounts/capabilities, shared mode0600 socket,
Herdr0.9.3/protocol22, packaged callback SHA256, no chat plugin content, web/Runtime/worker restart,
five-connection pool exhaustion and recovery with a two-second timeout, and pending-migration startup rejection.
Synthetic fixture checks pass: durable job replay/content guards, expired leases/stale tokens/uncertain effects,
closed worker dispatch after restart, two callback threads without crossing, replay deduplication,
changed-body rejection and stale generation rejection through the actual packaged Runtime callback client.
No authenticated Mattermost post or provider session is exercised by these fixtures.

Project cleanup succeeds; label-based checks find no remaining project containers, volumes or networks.
Own unique image tags are removed. Temporary callback marker file is removed and synthetic sessions invalidated.
Machine-readable sanitized evidence and exact tested image IDs: `evidence/local-compose.json`.

## Tested source

- Reviewed component main including migration correction: `cc053ce173e49d23a813119ab2d8a91907f606a3`.
- Exact reviewed backend correction: `b45cf0aa827dd19c81e9791c7b5e82ef8d0e36d0` (verified ancestor).
- Frozen root candidate: `aee60f8f677681c3b6cfee9d6958ce86f4e05296`.
- Exact passing test source: `2405f04c5f2eb5783f2d3f685444fd3c3236b21a`.
- Worktree: `/tmp/digitaltwin-integration-test`; branch: `test/integration`.

## Passed preparation and independent checks

- `python3 -m unittest discover -s tests -v`: 14 root Compose contract checks pass; live suite skips without opt-in.
- `scripts/acceptance dependencies`: PostgreSQL own-role access succeeds twice; cross-database access denied twice;
  reviewed derived Mattermost 11.11.1 native health and ping pass; own disposable resources removed.
- `scripts/acceptance runtime-offline`: real Herdr 0.9.3/protocol22 compatible server;
  socket UID10001/mode0600 accessible from a second UID10001 container; own disposable resources removed.
- Combined callback image, backend image and derived chat image build successfully with unique local tags.
  Callback staging/checksum enforcement was retained, not bypassed.

## Historical combined first-boot failure — corrected by reviewed PR13

This failed against original reviewed backend `53c69b7`/main `0c79c777`, before the correction above.

```sh
DIGITALTWIN_RUN_COMPOSE_TESTS=1 \
  DIGITALTWIN_REVIEWED_BACKEND_REVISION=53c69b7d537b906a06303461c658f62b990f23d9 \
  python3 -m unittest discover -s tests -v
```

Result: exit 1; 14 configuration checks pass; combined suite setup fails before any of its six tests execute.
The actual `backend-migrate` container runs the unmodified `bundle exec rake db:migrate` and exits 1:

```text
NoMethodError: undefined method 'pg_jsonb' for module Sequel
/app/db/migrate/004_workflows.rb:15
column :artifacts, :jsonb, null: false, default: Sequel.pg_jsonb({})
/app/lib/tasks/db.rake:67
```

The real Rake entry point opens a migration connection without loading the JSON extension needed by migration004.
Component setup that first opens the application connection loads that extension and does not reproduce the clean subprocess path.
The independent test preserves the migration gate; no fixture, Compose override or startup shim bypasses the failure.
Backend owner corrected the real entry point in reviewed commit `b45cf0a`, merged as `cc053ce`.
The independent rerun above confirms the correction without a Compose or fixture workaround.

Each attempted run used a fresh unique project/random loopback ports and public DB samples only.
Class cleanup removed its containers, named volumes, networks and unique image tags.
Post-cleanup project-label queries confirmed no containers/volumes/networks remained.
No other worker resources were removed. No session fixture/token file was created because setup failed first.

## Evidence boundaries

Dependency health and offline Runtime health are live local checks, not authenticated chat/provider compatibility.
Job/callback fixtures now pass on the combined stack and remain explicitly synthetic evidence.
Whole-project Sorbet remains failing as disclosed by the backend handoff; root integration does not clear it.
Authenticated chat/bot permissions/reconnect, four CLI handshakes, Writer settled state, selected Commander MCP,
signed mobile push/deep links, encrypted restore, image publication and production remain open.
Full Phase 0 acceptance is not claimed. See README.md for the complete 32-row acceptance-scope mapping.

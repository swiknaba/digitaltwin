# Independent local integration evidence

No publication, production access, provider login, paid call, chat account creation, signing, or mobile-device test occurred.

## Tested source

- Reviewed component main: `0c79c77719713ca38417d5ea6da63ca6bc0fa401`.
- Exact reviewed backend: `53c69b7d537b906a06303461c658f62b990f23d9` (verified ancestor).
- Frozen root candidate: `aee60f8f677681c3b6cfee9d6958ce86f4e05296`.
- Isolated test merge before diagnostic commit: `edf6c2ed8d1f94ce3534f8803aaeaa33bd9fc607`.
- Worktree: `/tmp/digitaltwin-integration-test`; branch: `test/integration`.

## Passed preparation and independent checks

- `python3 -m unittest discover -s tests -v`: 14 root Compose contract checks pass; live suite skips without opt-in.
- `scripts/acceptance dependencies`: PostgreSQL own-role access succeeds twice; cross-database access denied twice;
  reviewed derived Mattermost 11.11.1 native health and ping pass; own disposable resources removed.
- `scripts/acceptance runtime-offline`: real Herdr 0.9.3/protocol22 compatible server;
  socket UID10001/mode0600 accessible from a second UID10001 container; own disposable resources removed.
- Combined callback image, backend image and derived chat image build successfully with unique local tags.
  Callback staging/checksum enforcement was retained, not bypassed.

## Confirmed combined first-boot failure

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
Backend owner must fix and review the real entry point before combined execution can pass.

Each attempted run used a fresh unique project/random loopback ports and public DB samples only.
Class cleanup removed its containers, named volumes, networks and unique image tags.
Post-cleanup project-label queries confirmed no containers/volumes/networks remained.
No other worker resources were removed. No session fixture/token file was created because setup failed first.

## Evidence boundaries

Dependency health and offline Runtime health are live local checks, not authenticated chat/provider compatibility.
The prepared job/callback fixtures remain unexecuted on the combined stack at this checkpoint.
Whole-project Sorbet remains failing as disclosed by the backend handoff; root integration does not clear it.
Authenticated chat/bot permissions/reconnect, four CLI handshakes, Writer settled state, selected Master MCP,
signed mobile push/deep links, encrypted restore, image publication and production remain open.
Full Phase 0 acceptance is not claimed. See README.md for the complete 32-row acceptance-scope mapping.

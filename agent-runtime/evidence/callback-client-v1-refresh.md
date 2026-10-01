# Frozen callback client v1 — 2026-10-01

Follow-up baseline: `dc993b09c01c88621d9471c2027eba827f391515`.
Only the backend-owned artifact checksum and its provenance records change.
The original PR10 handoff remains historical evidence for the earlier artifact.

Source owner/path: `integration-backend/bin/digitaltwin`.
Frozen artifact SHA256:
`cd7dd6f80e050b91387c92fa285964f19ed089bb84b44c8dbb0dd5caf8478054`.
Previous artifact SHA256:
`a062e47b3e196256e0ee5a75f63084645835072ac9bf6a9c0d73d41be0dcf7d1`.
The backend owner reports formatting-only changes and froze these bytes.
No maintained client copy was added to agent-runtime.

Backend source was still uncommitted during the original fixture verification.
The frozen file is committed at `81d5d5c714c73890efccff172103f65171ecde20` and remains identical in reviewed backend
head `53c69b7d537b906a06303461c658f62b990f23d9`, merged via `0c79c77719713ca38417d5ea6da63ca6bc0fa401`.
The integrator independently verified both committed sources against the frozen SHA256.
The build retains exact checksum enforcement rather than accepting replacement bytes.

Checks passed against the frozen single-file named build context:

- Actual Linux AMD64 `with-callback` image build, using cached unchanged tool layers.
- Build-time checksum enforcement reports `/usr/local/bin/digitaltwin: OK`.
- Packaged file SHA256 independently matches the frozen source SHA256.
- Existing `callback-smoke.py`: exact POST path, Bearer header, generation/key/text,
  accepted/rejected responses, no automatic retry, no credential/body output and
  unavailable artifact-ready callback. This uses a disposable HTTP fixture.
- `git diff --check`.

Local image ID: `sha256:66d99f34a0ada9f408babd58f4fa333745af0388dcbc698107efb68bceda1bf5`.
Uncompressed size: `2155516501` bytes. This image was not published or deployed.
No full tool-suite rerun was needed: no tool, shell, startup or contract code changed.
Provider idle/MCP and full Kirei/source-thread delivery gates remain open.

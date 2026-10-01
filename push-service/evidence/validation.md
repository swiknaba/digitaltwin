# Push worker validation — 2026-10-01

Baseline: `7889c1a64856d75267ae6030db1743517b6a1342`. Isolated branch `build/push-service`; writes limited to `push-service/`.

## Exact provenance and notices

- Source tag `v6.6.0`, annotated tag object `1a3b58c47b9956f08af4651b3dbbfe81fefbd245`, commit `20f2a046fef76a7ab1c121cd01bc2b06206979be` fetched from the public Mattermost repository.
- Actual image pinned by AMD64 digest in `artifact.lock.json`, Docker Engine 29.8.0 on macOS ARM64 with AMD64 emulation.
- Actual `-version`: GitVersion `v6.6.0`, BuildHash `20f2a04`, BuildVersion `6.6.0`, tree `clean`, Go `go1.26.3`, platform `linux/amd64`.
- Source and image LICENSE SHA256 both `08ae49ca2907c9eb72cd323902028c4f4f48a628650dae01945ee401a603e9fb`; NOTICE both `0ef1f0c06b299198fe61ceffa3badd198d3593354cf4fd5eeea698252990472a`. Exact upstream copies retained under `licenses/`; upstream license is Apache 2.0.
- Pinned config sample SHA256 `cc7ec74b73b463abacfa3581e6ac5a553063e765e267d8b60d8ab83e186211ca`; source config struct SHA256 `d97e92adca7f1ecb91599a9f4c050985425e71ef871b47fe7ec34b399a0558c5`; source server SHA256 `a46024e1d72ff17a2a1007a98731e1d1fe9e044be44d61e8396b6ff210f915f7`.
- [binary-build-info.txt](binary-build-info.txt) captures the actual artifact's Go dependencies/checksums and exact VCS revision, from `go version -m`. Full transitive license review and OS-package/security audit remain open; matching top-level notices is not a complete artifact audit.

## Executed checks

| Command / check | Actual result |
| --- | --- |
| `python3 -m unittest discover -s push-service/tests -v` | 4 tests passed; rejects bad fields/timeouts, unsafe secret paths/inline passwords, duplicate/incomplete provider definitions; distinguishes local from delivery configuration |
| `python3 push-service/bin/check-config.py push-service/config/local.json` | Passed |
| `python3 push-service/bin/check-config.py --delivery push-service/config/delivery.example.json` | Structure passed; placeholder metadata is not actual identity validation |
| `docker compose -f push-service/compose.local.yml -p digitaltwin-push-20261001 config --quiet` | Passed |
| Same project `up -d --wait` | Actual pinned proxy healthy, user `nobody`, UID/GID 65534, internal network, no published host port |
| `python3 push-service/bin/smoke.py digitaltwin-push-20261001-push-proxy-1` | Passed: version/source hash, root health, 10 repeated malformed/missing-field/missing-platform JSON failures with HTTP 200, React Native `-v2` route parsing, GET send route rejects with HTTP 404 |
| Same project `restart push-proxy`, then actual `/version` | HTTP 200, `{"hash":"20f2a04","version":"6.6.0"}` |
| Pinned image `--network none -config /missing-config.json` | Expected exit 1; missing config file |
| Separate network-disabled image with delivery template and missing secret mounts | Both provider clients log failed initialization; `/version` still HTTP 200. Confirms health cannot attest provider readiness |
| Full pinned upstream `go test -count=1 ./... -v` plus injected component retry tests | Passed in Go 1.26.3 image `golang@sha256:2d6c80227255c3112a4d08e67ba98e58efd3846daf15d9d7d4c389565d881b1a`; selected output retained in [upstream-test-results.txt](upstream-test-results.txt) |
| `sh -n push-service/bin/check-upstream.sh`, `git diff --check` | Passed |

Retry tests call unchanged upstream implementations with synthetic provider HTTP transports: APNs recovery after a failed transport, no proxy retry of provider rejection, total deadline, maximum three attempts; FCM real SDK error decoding identifies internal/quota errors as retryable and invalid/auth errors as permanent. These are offline component tests, not APNs/FCM service compatibility success. Existing upstream tests include missing/bad FCM file initialization. No developer accounts, push credentials or signed builds were created.

Initial checks exposed two test assumptions: upstream rejects GET send route with 404; constructing a look-alike Firebase error cannot exercise SDK-private error classification. Tests were corrected to actual route behavior and real SDK decoding. Host Go toolchain fetch timed out; the digest-pinned disposable Docker toolchain completed the suite.

## Handoff and open gates

Ruling: this assigned upstream-configuration scope prepares Task 1/12 evidence; it does not claim the entire Phase 0 plan or dependent Tasks 6–10 complete. Shared Compose/contracts stay integrator ownership. Using an internal provider-free service without a published host port keeps tests isolated; provider egress is an explicit infrastructure delivery change. Wrong integration of those network settings would block delivery, so the README distinguishes them.

Author reviewed the final component diff; no additional orchestration session was started. Independent integration testing is the parent/integrator's authorized next stage. No merge or production deployment performed.

Still open: live selected-server generated push request, own signed mobile foreground/background/device delivery and correct channel/thread deep links, real credential validity/identity matching, complete transitive/OS license-security audit, production storage/secret projection/egress, and encrypted restore/rotation acceptance. Operator provides matching APNs key/team/key-ID/topic/environment and FCM service account/project plus signed apps/devices. Those requirements do not block the provider-free build/config checks.

Disposable project `digitaltwin-push-20261001` and missing-secret container removed after checks; other workers' containers were untouched. Worktree/branch preserved for PR review.

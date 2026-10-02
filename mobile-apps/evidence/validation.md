# Mobile worker validation — 2026-10-01

Baseline: `7889c1a64856d75267ae6030db1743517b6a1342`.
Branch: `build/mobile-apps`; isolated worktree `/tmp/digitaltwin-mobile-apps-20261001`.
Only `mobile-apps/` is changed. Source/contract identities are in the adjacent JSON
records and `../source.lock.json`. Logs remain ignored local build evidence.

| Check | Actual result |
| --- | --- |
| Fetch pinned public mobile source; no private submodules | Exact HEAD verified; inspected build/dependency/contract/license files SHA-256 verified. |
| `bin/check` | Six wrapper tests pass, including disposable real pinned checkout preparation and tamper rejection. Invalid config/revision and restricted-tool exclusion are exercised. |
| `npm ci --ignore-scripts --no-audit --no-fund` | 1,609 packages installed from upstream package-lock. Upstream deprecation warnings occurred; no provider session. |
| `bin/dependencies js` | Real pinned Node/npm preflight, dependency install, upstream patch-package, font copying and asset/glyph generation passed. FSL CLI exclusion also executed on the resulting tree. |
| Upstream targeted Jest | Three suites / 67 notification and deep-link tests pass. These are upstream unit tests using mocks, not live provider/device tests. |
| Upstream full Jest | 697 suites / 9,353 tests and 320 snapshots pass; two suites / six tests skipped by upstream. Worker teardown warning reported; no failing suites. `--watchman=false` avoids touching host Watchman state. |
| Upstream `npm run check` | ESLint and TypeScript `--noEmit` pass. npm warns about an existing host `init-package-manager` user configuration; no user config changed. |
| Prepare own unsigned configuration | Example app ID, labels, iOS groups/extensions and pinned notice URL generated; upstream Firebase client config removed. All recorded hashes verify after dependency preparation. |
| Chat/push contract | Source-bound server 11.11.1 / proxy 6.6.0 endpoint, v2 routing and thread fields agree. No authenticated mobile runtime/device test. |
| Android unsigned `mobile build android` | Exit 1 at preflight: SDK 36/build-tools 36.0.0/NDK 27.1.12297006 missing. Host has SDK 35/build-tools 35.0.1; not silently substituted. No native compile/output. |
| iOS simulator `mobile build ios` | Exit 1 at preflight: Ruby 3.2.11 and Bundler 2.5.11 absent. Xcode 27.0/27A266a and SDK 27.0 inspected. No native compile/output. |
| Script validation | Python compilation, Bash syntax and `git diff --check` pass. Unsigned artifact collector has no real artifact to test. |

The full suite/static checks were repeated after excluding the FSL Sentry CLI
packages and preparing our app configuration. Initial test invocations were
corrected for upstream's incompatible `--runInBand`/`--maxWorkers` combination
and host Watchman permissions; the successful commands disable Watchman and use
four workers. No host security setting or persistent login configuration changed.

## License findings and unresolved scope

The npm metadata inventory covers 1,631 entries, with 11 missing license fields
and nine FSL-1.1-MIT Sentry CLI/platform entries. `bin/exclude-build-tools`
removes those restricted build tools; it leaves the MIT SDK and original lock
intact, and native builds reject an installed CLI. SDK telemetry and upload hooks
remain disabled. Their exclusion has JS regression evidence, **no native build
evidence**. Exact installed native/transitive/output and bundled module audits,
required notice retention and branding approval are still release gates.

Native compilation, bit-for-bit repeatability, unsigned packaging with actual
outputs, own signed physical devices, foreground/background/terminated push,
network reconnect, privacy modes, deep links and owner interview acceptance remain
open. Operator inputs are listed in `../operator-inputs.md`. No developer enrollment,
signing material creation, paid signup, provider push, store upload or deployment
was attempted. No Phase 1 LiveKit/voice work was implemented.

## Integrator proposals

Reference the mobile tuple/evidence and open operator gates in shared
`docs/interfaces/mobile-push.md` and license/acceptance records. Keep Calls/rtcd
and Agents plugins excluded on the server. A root CI workflow can run
`mobile-apps/bin/ci js` from a fresh Linux/macOS checkout with the locked Node/npm,
and later `ci android`/`ci ios` on operator-provided native runners. Root workflows,
Compose, shared docs and tests remain integrator-owned and unchanged here.

## Execution rulings

- Implement only the independent mobile portion of Task 1 and the component brief;
  Tasks 6-10 live gates remain unchanged. No mobile source inspection clears them.
- Use the plan's executing-plans and verification skills inside our assigned folder;
  this evidence file serves as the scoped progress/handoff ledger. Avoid new
  orchestration sessions; independent integration testing belongs to the parent.
- Preserve upstream's real unsigned target; no fabricated signing patch or mocked
  native build success. Native source/dependency audits and delivery are open gates.


## PR #9 independent review follow-up

Two reviewed validation gaps were corrected in the mobile-only follow-up:

- Prepared-source changes now compare both index and working tree against HEAD,
  using NUL-delimited names. A regression stages an unrelated source file and
  checks rejection both before and after removing its working-tree copy. It
  reproduced acceptance before the fix and passes after the fix.
- APK packaging no longer treats an apksigner failure as proof that signatures
  are absent. The validator requires a complete single-disk non-ZIP64 ZIP with
  consistent local/central records and CRCs, no v1 signature material, and no
  unaccounted bytes before the central directory. That last requirement rejects
  both intact and corrupted v2/v3 signing-block structures. Ambiguous structures
  fail closed rather than being collected as unsigned.

Thirteen component tests pass, including unsigned structural positive fixtures
and the actual collector archive/notices path, plus v1, v2/v3, corrupted-magic, payload-tamper, malformed and trailing-data negative
fixtures. These fixtures use no signing keys and do not claim an installable
native APK. Prepared-source verification, Python compilation, Bash syntax and
Git whitespace checks pass. Native toolchain/device/output audit gates above
remain unchanged; neither native build nor real-artifact packaging is verified.

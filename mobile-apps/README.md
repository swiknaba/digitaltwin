# Mobile apps

Pinned public Mattermost Mobile `release-2.44`, commit
`c2fe3beda22befd2178dce431793c09111ed903e`, provides the iOS/Android chat client.
This folder owns independently authored preparation, unsigned build, check and
local packaging recipes. No upstream tree or dependencies are vendored.

[Source and toolchain lock](source.lock.json) binds source, dependency locks,
license/NOTICE, build configuration and inspected chat/push code by SHA-256.
[Validation](evidence/validation.md) records actual checks and open gates.
[Compatibility](compatibility.md), [operator inputs](operator-inputs.md),
[patch inventory](patches/README.md) and [license boundaries](NOTICES.md) are
part of the release handoff.

## Why this exists

Mattermost Mobile already implements native chat, threads and push in React Native,
so maintaining a small recipe avoids writing two clients. Mobile is released
separately because app identities, native toolchains, signing and device delivery
have a different lifecycle from the server. We could drop these builds if a future
chat client/platform meets our thread, privacy and self-hosted push requirements
without our own signed apps; replacing Mattermost means revalidating those APIs.

## Reproduce offline checks

Use Node **24.15.0** and npm **11.12.1** on PATH. Python 3.10+ and Git are
required by our small build wrapper. A fresh CI checkout runs:

```sh
mobile-apps/bin/ci js
```

This fetches the exact public revision without private submodules, verifies
checksums and a clean tracked tree, installs `npm ci --ignore-scripts`, excludes restricted Sentry CLI build tools, applies
upstream's pinned dependency patches, generates assets/fonts, runs our component
checks and upstream Jest, lint and TypeScript. Dependency retrieval needs network
access; the tests themselves use offline upstream fixtures/test doubles.
No provider, signing or Firebase account is accessed.

For incremental checks after fetch:

```sh
mobile-apps/bin/check
mobile-apps/bin/dependencies js
mobile-apps/bin/check upstream
(cd mobile-apps/upstream && npm run check)
```

`check` runs six wrapper tests when pinned source exists; the preparation test
skips when it has not been fetched. It clones only this pinned public checkout
into a disposable directory. `fetch` refuses a dirty or wrong revision checkout;
it never resets operator work. Prepared checkouts use `verify-prepared`, while
initial checkouts use `verify`. Use a fresh component checkout for each CI build.

## Unsigned native runners

The selected pins are in `source.lock.json`. Upstream selects Node 24.15.0,
Ruby 3.2.11, Bundler 2.5.11, CocoaPods 1.16.1, Gradle 9.0.0, Kotlin 2.2.21,
SDK/build-tools 36/36.0.0 and NDK 27.1.12297006. Our initial runner selection
adds exact npm 11.12.1, observed Xcode 27.0 (27A266a)/SDK 27.0 and observed Java
17.0.4.1. Upstream CI requires Java major 17 and Xcode >=26.1; the selected
exact runners have **not** been validated by native compilation. The old local
Java patch is a reproducibility record, not security approval for distribution;
review and update the exact JDK before release. Do not auto-upgrade tools during
a build. SDK/package licenses and installed runner images are operator-owned.

Copy `config/app.example.json` to ignored `operator.json` and select your own
application ID, HTTPS server and app label. The example domain/ID is a placeholder.
No signing keys or tokens belong in this configuration.

```sh
mobile-apps/bin/mobile doctor android
mobile-apps/bin/ci android mobile-apps/operator.json
# Android additionally requires ANDROID_HOME and MOBILE_FIREBASE_CLIENT_FILE.

mobile-apps/bin/mobile doctor ios
mobile-apps/bin/ci ios mobile-apps/operator.json
```

Android calls upstream `:app:assembleUnsigned`, whose signingConfig is null.
iOS builds the `Mattermost` Release simulator target with signing disabled,
blank DEVELOPMENT_TEAM and no provisioning updates. Its local Xcode environment
pins the checked Node executable to survive upstream's nvm initialization. Native dependencies use
frozen Bundler and CocoaPods `--deployment`; new lock resolutions fail rather
than silently updating the recipe. The Gradle wrapper receives the official
9.0.0-all distribution checksum. We do not call upstream Fastlane signing,
private-repository, S3, TestFlight, store-upload or messaging lanes.

Android output is under `upstream/android/app/build/outputs/apk/unsigned/`.
iOS simulator output is under `build/ios/Build/Products/Release-iphonesimulator/`.
The exact output filename is determined by the successful native runner.
No native artifacts were produced on the current host.

After inspecting an artifact, `bin/package-unsigned <artifact>` checks that it
is unsigned using `apksigner` or `codesign`, and collects it with unmodified
upstream LICENSE/NOTICE, input/patch hashes and an explicit open license/device
gate into ignored `dist/`. It rejects signing files and symlinks. This collector
is prepared but unverified with a native artifact. It performs no upload.

“Reproducible” here means fixed source, tools, lock inputs and repeatable commands;
bit-for-bit native outputs require two successful clean builds and are unverified.

## Updates

Select a reviewed upstream revision and exact compatible server/proxy versions.
Inspect security changes, dependency/native license changes and upstream patches;
regenerate all input hashes and revise the narrow preparation logic when paths
change. Run fresh JS checks, unsigned native builds and compare artifact hashes
on two clean runners. Audit output notices/branding, then repeat the signed-device
matrix in `operator-inputs.md` before releasing with separately authorized signing
and distribution tooling. Preserve old provenance, rollback artifacts and app IDs.
Production infrastructure and server/proxy ownership stay with their owners.
LiveKit, voice UI, Calls/rtcd services and future LiteLLM/MCP work are excluded.

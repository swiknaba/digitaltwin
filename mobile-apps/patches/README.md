# Patch inventory

No maintained upstream source patch files and no copied application modules.
`bin/mobile prepare` authors a narrow local configuration change against verified
source, records each changed file's hash in ignored `upstream/.digitaltwin/prepared.json`,
and rejects unexplained changes before compilation.

- Android applicationId changes; its upstream namespace/Java packages remain intact.
- iOS main, notification-service and share bundle IDs, app group and keychain
  identifiers change together by replacing the exact upstream `com.mattermost.rnbeta` prefix.
- Android launcher label and iOS main display label change to the configured name.
- `assets/override/config.json` selects the server/name, disables Sentry/Rudder
  configuration, and links the notice at the pinned revision.
- The Gradle distribution receives its official SHA-256 checksum.
- Upstream Android Firebase client configuration is removed. Operator supplies
  the matching app's public client JSON. It is never a Firebase service-account file.

The dependency recipe excludes the exact FSL Sentry CLI 3.4.1/platform packages
from installed node_modules. This changes build-tool contents only; the upstream
lockfile and MIT Sentry SDK are preserved. Unknown restricted package/version
changes fail the exclusion step and require review.

Upstream dependency patches under its `patches/` are applied unchanged by the
pinned `patch-package` executable. They remain upstream-owned Apache-source
changes with each dependency's original license. LICENSE.txt and NOTICE.txt
stay byte-identical. Generated fonts/assets are upstream build steps, not a fork.
We use the real unsigned Gradle target rather than changing signing behavior.

Icons, artwork, custom URL/SSO schemes and universal links are not rebranded here.
The inherited scheme behavior must be reviewed for collisions before distribution;
a product branding patch needs separately reviewed assets and updated provenance.
No license checks or commercially gated modules are modified.

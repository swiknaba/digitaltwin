# Source, dependencies and notices

Mattermost mobile source at the locked commit has an Apache 2.0 LICENSE.txt and
NOTICE.txt. Fetch retains both; unsigned packaging includes byte-identical copies.
The in-app notice link points at that exact revision, and the app's upstream
About/notice behavior stays intact. Our wrapper scripts and configuration are
independently authored repository code. Do not infer that all dependencies share
Apache 2.0 or that the official server's compiled MIT license covers mobile.

[evidence/license-inventory.json](evidence/license-inventory.json) inventories
npm lockfile license metadata, including missing entries. Nine Sentry CLI 3.4.1/platform entries declare FSL-1.1-MIT. The dependency
recipe deletes these build tools immediately after lockfile installation and
before running patches/assets/tests/native tasks; native builds reject their
presence. MIT Sentry SDK libraries remain with telemetry/build-upload hooks
disabled. No Sentry CLI install script/binary is executed. Registry cache files
are build cache, never release artifacts. Native compilation after this exclusion
is unverified and remains a release gate. The inventory is a starting record,
not legal clearance: inspect actual installed package LICENSE/NOTICE files,
Git dependencies, CocoaPods, Gradle/native/transitive components, upstream
bundled product modules and final binary resources before distribution. Preserve
every required notice and any source obligations. Audit incompatible components
before release; do not remove gates to unlock paid services.

The private Intune submodule is deliberately not initialized, installed or enabled.
Public source contains dormant Calls, Agents and Playbooks client support and
Apache-labeled Calls dependencies. No Calls/rtcd server or Agents plugin is added,
and no LiveKit/voice integration is implemented. These existing upstream modules
are not evidence of a completed commercial-component audit or a voice deliverable.
The server owner must keep excluded plugins/services disabled. Omitting bundled
client modules from a distribution, if needed by the final audit, requires a
reviewed follow-up patch and native regression builds.

Mattermost marks/icons/artwork remain upstream. Our app IDs/display labels are
configurable; trademark/branding review and operator-supplied artwork are still
release requirements. Apple SDK/Xcode and the selected JDK/Android toolchain are
operator-provided runner dependencies; this repository does not redistribute them.
Signing keys, profiles, FCM service accounts and APNs credentials never belong in
source, build images, review archives or committed test evidence.

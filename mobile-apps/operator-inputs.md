# Operator inputs and device release gates

## Inputs before an unsigned native build

Provide a runner with the exact selected pins and accepted SDK license terms.
Set PATH to Node/npm and, for iOS, Ruby/Bundler; set ANDROID_HOME to SDK 36,
build-tools 36.0.0 and NDK 27.1.12297006 for Android. Do not change global Xcode
selection; an operator may set DEVELOPER_DIR for the runner. No developer
membership or signing credentials are needed for simulator/unsigned compilation.

Supply ignored `operator.json` with own reverse-DNS app ID, plain display name
and credential-free HTTPS server URL. `config/app.example.json` supplies the
shape, not approved product identities. Android native compilation also requires
matching **public Firebase Android client** google-services.json through
MOBILE_FIREBASE_CLIENT_FILE. It contains app/project identifiers and client API
configuration, not a service-account private key. Restrict and review that API
configuration in Firebase. Never pass a service-account credential file here.

## Separate future signing/distribution setup

No steps below were performed by this worker. The operator must choose
application IDs, approved branding/artwork and distribution channels first.

- iOS: own Apple team/enrollment, main/share/notification app IDs, matching app
  group and keychain entitlements, certificates/profiles, APNs topic, production
  or development environment, APNs key ID/team ID and private key reference.
  Review URL/SSO schemes, associated domains/universal links, privacy strings and
  supported deployment target (16.4). Keep signing/service keys outside Git and
  build images. Simulator output does not install on a physical device.
- Android: own package ID, matching Firebase project/client config, FCM service
  account reference in the proxy's runtime secret mount, operator-held signing
  keystore/alias/password references, update lineage, and distribution choice.
  An unsigned APK cannot provide signed-device acceptance.
- Server/proxy: infrastructure owner configures the server's private push-proxy
  URL and notification policy. Push owner configures `apple_rn` (or explicit beta
  target) and `android_rn` with the matching identities. Supply provider secrets
  through protected runtime mounts, never through app configuration or this repo.
- Lifecycle: define key access/rotation/revocation and profile renewal, retain
  previous signed app/version artifacts and provenance, and test rollback/update
  continuity with the same identities before distribution.

This folder supplies no signing or publishing command. Those operations require
operator-owned tooling and separate explicit authorization; no paid signup,
key/profile creation or upload is implied by running our unsigned recipes.

## Required evidence matrix

For both own signed iOS and Android builds, record app revision/patch hashes,
server/proxy artifacts, device OS/build version, selected notification privacy
mode, and sanitized observed results:

1. Authenticate to the selected server; join a real channel and start two threads.
   Send ordinary follow-up messages and verify replies stay under the proper root.
2. Receive foreground, background and terminated-app pushes with a locked screen;
   tap each and verify exact server, channel, thread and post. Repeat for CRT on/off.
3. Repeat with two registered servers; unknown/deleted channel, revoked membership
   and signed-out session must not expose content from another identity.
4. Interrupt/reconnect the network; verify history recovery, no missing/duplicated
   posts, and correct thread after opening an older delayed notification.
5. Verify full-content/generic/selected ID-only notification privacy and notification
   disable behavior. Record any unavailable server capability explicitly.
6. Test HTTPS post permalinks, configured custom URL/SSO return links, signing/update
   continuity and app group behavior for notification/share extensions.
7. Complete the Phase 0 owner threaded-agent interview on the own builds and prove
   self-hosted push opens its source thread. Attach sanitized evidence to acceptance.

Native voice, LiveKit UI, PushKit calling acceptance and store publication are not
part of these Phase 0 checks. Live provider delivery and device compatibility
remain unverified until operator setup is supplied.

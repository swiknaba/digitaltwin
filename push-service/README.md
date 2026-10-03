# Push service

Use the existing, unmodified Mattermost push proxy 6.6.0. No Kirei push server is built here. [artifact.lock.json](artifact.lock.json) records the source commit and OCI digests; the local recipe consumes the AMD64 artifact and runs under emulation on ARM64 hosts.

## Why this exists

We self-host the existing upstream push proxy so our custom mobile apps can use our own APNs/FCM credentials without depending on paid production hosted push. The proxy itself is Apache 2.0; we consume its verified artifact instead of inventing another server. It is a separate deployable because provider credentials, network access, upgrades and failures belong to the notification path, independently of Kirei and chat storage. We could drop or replace it if a future chat platform provides built-in push that meets our custom-app, self-hosting and thread-opening requirements.

## Disposable local checks

From the repository root in your component worktree:

```sh
python3 -m unittest discover -s push-service/tests -v
python3 push-service/bin/check-config.py push-service/config/local.json
docker compose -f push-service/compose.local.yml -p digitaltwin-push-YOUR_UNIQUE_ID config --quiet
docker compose -f push-service/compose.local.yml -p digitaltwin-push-YOUR_UNIQUE_ID up -d --wait
python3 push-service/bin/smoke.py digitaltwin-push-YOUR_UNIQUE_ID-push-proxy-1
docker compose -f push-service/compose.local.yml -p digitaltwin-push-YOUR_UNIQUE_ID down --volumes
sh push-service/bin/check-upstream.sh
```

Choose a unique project name per run. The local proxy has empty provider targets, no published host port, and an internal network without provider egress. The smoke reads that config before sending only synthetic failing requests. The upstream checker fetches verified public source into a disposable directory and uses a digest-pinned Go 1.26.3 container. Its HTTP transports are synthetic; no credentials or developer enrollment are involved. Dependency downloads require network access. It tests real upstream retry/error code, not device delivery.

## Startup and health contract

| Setting | Pinned upstream contract |
| --- | --- |
| Artifact | `mattermost/mattermost-push-proxy:6.6.0` |
| Process | Existing entrypoint execs `/mattermost-push-proxy/bin/mattermost-push-proxy` |
| Arguments | `-config /mattermost-push-proxy/config/mattermost-push-proxy.json` |
| User | `nobody:nogroup`, UID/GID 65534 in inspected image |
| Listen | `:8066`, private Mattermost connectivity only |
| Health | `GET /version` returns JSON version `6.6.0`, hash beginning `20f2a04`; `GET /` serves static identification |
| Storage | Read-only config and provider secret mounts; no proxy database or delivery queue |
| Logging | JSON console logs, bounded externally; file logging disabled |
| Shutdown | SIGTERM/SIGINT invoke upstream graceful shutdown |

The provided healthcheck uses existing image `nc` and `grep`; it proves process liveness/version only. There is no provider readiness endpoint. Missing/invalid config exits; malformed config can be printed by upstream, so run the safe preflight first. Failed APNs/FCM client initialization is logged and omitted from the target map while the process remains alive. Review initialization logs privately and verify signed-device delivery before declaring provider readiness.

## Operator delivery configuration and secret references

[config/delivery.example.json](config/delivery.example.json) contains exact 6.6.0 configuration keys for the React Native targets `apple_rn` and `android_rn`. It is a template, not usable credentials. Replace the example topic, key ID, team ID, and environment with the identities selected by the mobile owner. Beta iOS tokens use a different `apple_rnbeta` target and are outside this stable-app recipe; do not ship a beta build with the stable target configuration.

```sh
python3 push-service/bin/check-config.py --delivery /outside/git/push-config.json
```

This validates our restricted recipe, including positive timeout bounds and native mounted-file paths. It does not resolve references, inspect key contents, confirm app identities, or attest provider readiness. No new upstream ENV or `_FILE` variables are invented. Upstream reads JSON with `-config`, APNs `AppleAuthKeyFile`, and FCM `ServiceFileLocation` directly. Our recipe uses APNs token authentication; certificate/password authentication remains an upstream alternative outside this recipe. The deprecated `AndroidApiKey` is excluded.

[config/secret-references.schema.json](config/secret-references.schema.json) defines the infrastructure handoff manifest; [the example](config/secret-references.example.json) stores only `op://` references. Infrastructure resolves these references outside this repository, or supplies equivalent operator-managed files without 1Password. The proxy never receives the manifest or interprets `op://`. Mount the materialized APNs key and FCM JSON read-only at their stated paths. Root-owned host secret material stays mode 0600; the hosting platform must project readable secrets for UID 65534 without making host files public. Do not simply bind root-only files into a non-root container and assume they are readable. Keep credentials out of Git, images, logs, and build contexts.

For provider delivery, infrastructure must allow APNs/FCM outbound HTTPS, use its trusted internal server route, and preserve private inbound access. The offline internal network deliberately blocks that access. Upstream 6.6.0 does not authenticate inbound push requests; restrict it to the Mattermost server network. Provider credentials and production TLS/lifecycle remain operator ownership.

## Compatibility and retry behavior

See [compatibility.md](compatibility.md) for source-bound inspection and live evidence limits. Mattermost sets `EmailSettings.SendPushNotifications=true` and `EmailSettings.PushNotificationServer` to the base URL, for example `http://push-proxy:8066`; it appends `/api/v1/send_push`. The integrator owns root Compose and environment edits.

Push JSON response `status` is `OK`, `FAIL`, or `REMOVE`. HTTP 200 alone is insufficient. `REMOVE` means remove the expired/unregistered device token; `FAIL` needs diagnosis. The proxy has no durable queue or request idempotency guarantee. Do not add an independent blind retry sender around upstream, particularly after a timeout with unknown delivery.

Upstream attempts at most three sends with exponential waits starting at one second. Our config sets the send/retry contexts to 30 seconds overall and 8 seconds per attempt; these contexts do not bound FCM OAuth token acquisition. APNs transport errors retry; APNs rejection responses are handled without proxy-level retry. FCM deadlines, internal errors and quota errors retry; revoked auth and invalid arguments do not. Firebase's SDK independently handles some unavailable responses. Deadline retries can duplicate notifications; no exactly-once delivery claim is made. Tests cover APNs transport recovery, permanent response, retry-context timeout and attempt cap, plus real Firebase SDK error decoding/classification and missing/bad credential initialization.

FCM authentication is an upstream readiness limitation: 6.6.0 constructs its send token source with `context.Background()`. OAuth2 0.36.0 synchronously obtains a token before sending and uses that token source's context and default HTTP client, which has no overall timeout. A stalled token endpoint can therefore outlast the 30/8-second send/retry contexts. The separate credential-expiry check uses a bounded context, but it does not bound the send token source. Our synthetic FCM tests use `WithoutAuthentication()` and cannot prove OAuth timeout behavior. Process health can remain successful while authenticated delivery stalls. Bounded end-to-end FCM delivery under token-endpoint network faults remains an unmet readiness requirement, to be tested and resolved through upstream or an operator-reviewed mitigation before production acceptance; no upstream fork or credential change is introduced here.

## Upgrades, rotation and recovery

Keep proxy configuration and app identities together with the selected server/mobile pins. Before changing a pin: resolve the source tag/commit and image digest, inspect config/protocol changes, retain upstream LICENSE/NOTICE, review compiled dependencies, rerun local and upstream checks, then obtain signed iOS/Android foreground/background and thread-opening evidence. Source inspection is not live compatibility acceptance.

For rotation, the operator materializes replacements outside Git, updates secret projections/config together, restarts the unmodified proxy, inspects initialization, then verifies both signed apps. Keep previous approved artifact/config references for rollback; do not reuse revoked credentials. Rollback requires operator approval of credentials still valid with the matching apps.

Backup encrypted proxy configuration, identity metadata and secret references through infrastructure. Restore the selected digest and config, recover or reissue provider secrets through the operator's secret system, then check process health, target initialization and device delivery. The proxy itself has no persisted delivery state to restore. Infrastructure owns backup scheduling/encryption/retention and production deployment.

Exact source/artifact notices and recorded checks are in [evidence/validation.md](evidence/validation.md). Full transitive license/security review and signed-device acceptance remain open; no production deployment or provider access occurred here.

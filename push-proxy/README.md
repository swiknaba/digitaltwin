# Mattermost Push Proxy

Configuration and release ownership for the existing upstream Mattermost push proxy.
Own exact artifact pins, safe configuration examples, health/compatibility checks, and recovery guidance here.
Do not build a new push gateway inside Kirei.

## API and Configuration Contract

- Receive notifications from Mattermost using the selected upstream proxy protocol.
- Deliver to APNs/FCM using operator-supplied credentials matched to our mobile application identities.
- Keep credentials outside Git/images; record secret references and rotation/recovery procedures.
- Coordinate server/proxy/mobile pins, background delivery, privacy settings, and correct thread deep links.

Validate request schemas, configuration keys, port, and health behavior against the pinned [upstream source](https://github.com/mattermost/mattermost-push-proxy).
No proxy endpoint or sample provider payload is invented by this scaffold.
VoIP/call integration remains Phase 1 even if upstream exposes call-related features.
Production TLS, storage, and lifecycle remain infrastructure responsibilities.

## Worker Scope

Prepare Task 1 and Task 12 configuration, provenance, licenses, compatibility, and restore evidence.
Offline checks can proceed independently; real APNs/FCM delivery requires operator credentials and signed mobile builds.

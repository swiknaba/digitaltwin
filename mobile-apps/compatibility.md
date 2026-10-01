# Chat and push compatibility record

Selected tuple: mobile `c2fe3beda22befd2178dce431793c09111ed903e` (2.44.0),
Team Edition 11.11.1, push proxy 6.6.0 source
`20f2a046fef76a7ab1c121cd01bc2b06206979be`.
[Source evidence](evidence/source-contracts.json) records inspected URLs/checksums;
[mobile input lock](source.lock.json) hashes the corresponding mobile files.
This is release-bound source inspection and offline tests, **not live compatibility**.

| Boundary | Verified source behavior | Remaining live evidence |
| --- | --- | --- |
| Chat posts/threads | Mobile `app/client/rest/posts.ts` uses POST `/api/v4/posts`, GET `/api/v4/posts/{id}/thread`, channel posts with `since`/thread options. Server `api4/post.go` registers matching authenticated endpoints. `root_id` distinguishes replies. | Authenticated mobile login, ordinary threaded replies and attachments on selected Team Edition. |
| Device registration | Mobile `setExtraSessionProps` PUTs `/api/v4/users/sessions/device` with `device_id`, string `device_notification_disabled` and `mobile_version`; server `user.go` handles the same route/fields. | Real session registration and provider tokens; permission/privacy settings. |
| Token routing | Mobile emits `apple_rn-v2:<token>` or `android_rn-v2:<token>`. An app ID containing `rnbeta` selects `apple_rnbeta-v2`. Server splits prefix/token at `:`; proxy `server.go` strips `-v2` and selects matching target. | Matching APNs topic/environment/key and Firebase project/service-account setup. |
| Notification fields | Proxy Android/APNs constructors preserve `channel_id`, `root_id`, `server_id`, post/team fields and CRT status; mobile maps `server_id` to a registered server and opens a thread when CRT is enabled and root exists. Otherwise it opens the channel. | Two-thread/two-server navigation, foreground/background/terminated-app push, revoked membership, missing server. |
| Reconnect | Mobile WebSocket uses `/api/v4/websocket` and reconnection/sync logic; upstream tests pass offline. | Interrupted real device network, REST recovery, no missing/duplicated replies. |
| Deep links | Upstream URL parser and notification navigation tests pass. | Own signed app URL schemes/universal links and correct thread on both platforms. |

Thread push requires CRT enabled in both selected server configuration and mobile
preferences; otherwise the source deliberately opens the channel. Do not claim
thread acceptance from merely seeing a notification. `server_id` must resolve to
a server the device has registered. The proxy target `apple_rn` must use our app's
APNs topic (our bundle ID), not its sample Mattermost topic. Android FCM sender
credentials must correspond to our public app client configuration. A beta-named
app additionally needs the `apple_rnbeta` target configured consistently.

The server owns notification content/ID-only privacy policy. Test generic,
full-content and any selected ID-only mode on locked and unlocked devices;
redact user names, message content, device tokens and provider identifiers from
stored evidence. Upstream fixture test success does not prove server license
availability of each privacy mode. No production providers were contacted.

Proposed integrator handoff: reference this tuple and evidence from shared
`docs/interfaces/mobile-push.md`; retain signed-device/thread acceptance as open.
No shared interface, Compose or root file is changed by this component.

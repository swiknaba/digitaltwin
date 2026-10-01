# Mobile Clients

Our maintained iOS/Android builds from pinned Apache 2.0 Mattermost mobile source.
Own build recipes, upstream revision records, patches, notices, component tests, and release/update pipelines here.
Fetch verified upstream source into ignored `upstream/`; retain our changes without vendoring unrelated repositories.

## API and Configuration Contract

- Use the selected Mattermost server's authenticated chat and native thread interfaces.
- Match app identities and push registration/configuration to our self-hosted push proxy and APNs/FCM credentials.
- Preserve correct thread deep links, foreground/background delivery, reconnect behavior, and notification privacy settings.
- Keep signing material and provider credentials outside Git/images. Record references and operator setup steps only.
- Own mobile build toolchain pins independently; verify compatibility with server/proxy releases.

Use the [upstream mobile repository](https://github.com/mattermost/mattermost-mobile) as the source and license starting point.
Selected app IDs, distribution channel, signing, Apple/Google enrollment, and device evidence remain operator setup work.
Phase 0 covers chat and push. Native calls, background voice, and LiveKit UI belong to Phase 1.

## Worker Scope

Prepare reproducible builds, the patch inventory, notices, CI checks, and chat/push compatibility evidence.
Separate offline build checks from signed-device/network acceptance; missing live evidence stays open.

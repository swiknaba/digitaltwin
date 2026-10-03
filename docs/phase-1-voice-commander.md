# Phase 1: Group Calls and AI Voice

Phase 1 independently integrates self-hosted LiveKit with Mattermost for group calls and AI voice conversation.
Voice uses the same Kirei Commander service, status registry, verified context, and operational tools as `@agent`.
Commander keeps its operational/emergency role; ordinary coding retains Writer/Reviewer gates.
Mattermost remains the chat UI and transport. No chat-plugin MCP integration is required.

## Services and Integration

Use the [Apache 2.0 LiveKit server](https://github.com/livekit/livekit/blob/commander/LICENSE) and separately hosted voice workers.
The [LiveKit Agents framework](https://github.com/livekit/agents/blob/main/LICENSE) provides an Apache 2.0 starting point for AI voice.
Audit chosen SDKs, adapters, transitive dependencies, model services, and shipped outputs before adopting them.
Hosting, speech/model inference, Apple/Google distribution, and network services still have operational costs.

Omit Mattermost Calls/rtcd and their commercial dependencies from the selected stack.
Build the LiveKit integration independently; do not copy paid modules or remove entitlement checks.
Expose authenticated call creation/join operations through a small external integration and client UI.
Use verified Mattermost user/channel/thread context when authorizing short-lived LiveKit room tokens.
Check current membership before joining; never infer authorization from an unverified display name or client-supplied user ID.
Keep service credentials and signing keys server-side.
Human setup supplies production domains, TLS, media routing/TURN, secrets, and service orchestration.

Support human group calls and a user-requested AI participant connected to the same Commander service.
The AI receives the call's verified source context and accesses existing typed tools through Kirei.
The voice adapter handles speech input/output, interruption, turn-taking, join/leave, and connection loss.
Do not assume chat notifications or a web plugin automatically supply native mobile call behavior.
Implement and validate call UI in the custom mobile clients and selected browser/desktop surface.
Verify iOS background audio/call lifecycle, Android background behavior, permissions, routing, and reconnect on real devices.
Document what happens when the app is suspended, the phone locks, or the network changes.

Maintain independent pins, patch inventories, licenses/notices, build pipelines, and security-update procedures for clients and services.
Keep mobile signing, APNs/FCM credentials, and deployment setup in the existing operator-owned process.
No credentials, commercial terms, deployments, or app-store submissions are created by this plan update.

## Validation and Acceptance

- Verify a human group call with authorized participants from browser and our iOS/Android builds.
- Join an AI participant and ask “What's blocked, and what changed since yesterday?”
- Return a concise answer with project names, current/stale status, and source links in the originating Mattermost thread or Commander channel.
- Support follow-up questions, interruption, explicit AI leave, and reconnect without duplicate tool execution.
- Reject unauthorized joins and expired tokens; test revoked channel membership and incorrect source context.
- Preserve destructive-operation confirmations and coding gates when voice invokes the existing Commander tools.
- Test background/locked-device audio, notifications, deep links, Bluetooth/headset routing, and network changes on real devices.
- Keep unanswered integration findings explicit; release only after the required device, license, and service checks pass.

## Deferred Commander Convenience: Workflow Thread Creation

Commander-created Mattermost workflow threads remain optional in Phase 0.
Include root-post creation there only if verified creation and retry reconciliation are straightforward.
Otherwise, retain existing-thread starts and implement the convenience here.

Validate the selected project channel and returned root post through the server API.
Kirei records the channel/thread association before starting a requested coding workflow.
Reconcile uncertain results without creating duplicate root posts, workflows, or sessions.
This convenience does not block Phase 0 acceptance or become a prerequisite for voice calls.

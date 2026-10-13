# Commander bridge core

This is the dependency-free, typed core for the operator-run Commander bridge. It is
not an OpenCode plugin and does not install arbitrary extensions. Its stable
responsibilities are:

- retain the one global Commander conversation identifier, bounded event history,
  and idempotent request records through restarts;
- replay bounded persisted events from the caller's acknowledged cursor; and
- require a newly consumed, short-lived user-, conversation-, action-, request-id-,
  and canonical-body-bound capability before every read, prompt, steer, or cancel
  action; and
- keep runtime credentials and capability proofs outside the renderer, project
  configuration, records, fixtures, and Git.

`CommanderBridgeHttpService` is the private bridge's parsed protocol service;
`createCommanderBridgeNodeListener` supplies the narrow Node adapter used for local
operator-owned loopback or HTTPS binding. It accepts only five POST routes, requires
JSON, caps a request at 64 KiB, and rejects unknown methods/routes. It deliberately
has no runtime event route.

`CommanderMainProcessTransport` is the desktop-side client. Its main-process-only
issuer receives the command action plus a SHA-256 binding of the request id and body;
the bridge verifier must match that binding atomically when it consumes the proof.
The renderer receives only typed success/failure results, never a proof. `open` and
`reconnect` use independently consumed read proofs so a renderer reload can resume a
durable event cursor without retaining credentials.

`RuntimeEventIngress` is a separate authenticated channel for runtime output. It
cannot consume a desktop proof and is intentionally not mounted by the user-action
listener. The deployment adapter must authenticate an operator-owned runtime identity
over a private Unix-socket/OS-ownership boundary or mutually authenticated service
channel. Do not reuse panel capabilities, project configuration, or a public HTTP
route for runtime events.

`EphemeralTestAuthority` is only a local test adapter: it creates random, one-use
proofs in process memory and writes no credential or identity state. Production must
provide an operator bootstrap that derives actor and conversation identity outside
the renderer/project, issues short-lived command proofs, and separately authenticates
the runtime identity. No production credential format or provider is assumed here.

`FileConversationStore` is the single-operator durable adapter; it atomically writes
only conversation/replay metadata with mode `0600`. A scaled deployment must replace
it with a transactional operator-owned store. `InMemoryConversationStore` is only a
deterministic test double. `CapabilityVerifier` is likewise an adapter whose
implementation must validate audience, actor, conversation, action, request binding,
expiry, and replay atomically. This component refuses to derive any actor or
conversation identity from panel input.

Run the current dependency-free tests with:

```sh
npm test
```

The command uses Node 22 type stripping solely to run the test suite while the pinned
OpenCode checkout's TypeScript toolchain is being repaired. It is not a replacement
for the upstream `tsgo` check, which remains required before the maintained UI patch
or bridge adapter can pass the Gate 1 implementation evidence.

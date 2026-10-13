# Commander bridge core

This is the dependency-free, typed core for the operator-run Commander bridge. It is
not an OpenCode plugin and does not install arbitrary extensions. Its stable
responsibilities are:

- retain the one global Commander conversation identifier, bounded event history,
  and idempotent request records through restarts;
- replay bounded persisted events from the caller's acknowledged cursor; and
- require a newly consumed, short-lived user-, conversation-, and action-bound
  capability before every read, prompt, steer, or cancel action; and
- keep runtime credentials and capability proofs outside the renderer, project
  configuration, records, fixtures, and Git.

`CommanderBridgeHttpService` is the private bridge's parsed protocol service and
`CommanderMainProcessTransport` is its desktop-side client. The latter gets one
ephemeral proof from a main-process-only issuer for each action and sends it only as
an Authorization header. It never returns the proof to panel code. Network binding,
route/method parsing, body limits, and the separate runtime-event channel remain
deployment adapters; the public user-action protocol deliberately has no event
ingestion route. The included loopback test uses only an in-memory verifier and
ephemeral proof.

`FileConversationStore` is the single-operator durable adapter; it atomically writes
only conversation/replay metadata with mode `0600`. A scaled deployment must replace
it with a transactional operator-owned store. `InMemoryConversationStore` is only a
deterministic test double. `CapabilityVerifier` is likewise an adapter
whose implementation must validate audience, actor, conversation, action, expiry, and replay
atomically. This component refuses to derive any actor or conversation identity from
panel input.

Run the current dependency-free tests with:

```sh
npm test
```

The command uses Node 22 type stripping solely to run the test suite while the pinned
OpenCode checkout's TypeScript toolchain is being repaired. It is not a replacement
for the upstream `tsgo` check, which remains required before the maintained UI patch
or bridge adapter can pass the Gate 1 implementation evidence.

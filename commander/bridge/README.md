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

The package root is a configuration-free OpenCode bundle entrypoint. The reviewed
Node bridge core is available through its explicit `@digitaltwin/commander-bridge/core`
subpath for a future operator-owned main-process bootstrap. `prepare-opencode.sh`
copies only this package manifest, strict TypeScript configuration, and SHA-256
allowlisted `src/*.ts` files into OpenCode's `packages/commander-bridge`; it never
copies this README, user project configuration, credentials, or operator state.

`CommanderBridgeHttpService` is the private bridge's parsed protocol service;
`createCommanderBridgeNodeListener` supplies the narrow Node adapter used for local
operator-owned loopback or HTTPS binding. Its panel surface accepts only five POST
JSON routes, caps a request at 64 KiB, and rejects unknown methods/routes. When an
operator explicitly supplies a private identity and receipt store,
`createOperatorCommanderBridgeNodeListener` additionally serves authenticated
FutureTask POST delivery and GET reconciliation under `/private/future-tasks`.
Those calls append a durable visible Commander notice and persist the receipt. It
deliberately has no runtime event route.

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

`createRuntimeEventNodeListener` and `listenRuntimeEventSocket` provide the narrow
Unix-domain deployment adapter for that channel. It creates no credential: the
operator supplies the runtime authenticator, and the adapter refuses to replace an
existing socket before setting its mode to `0600`. It has one runtime-only POST route
and cannot be mounted on the desktop listener. The deterministic test uses only
`EphemeralTestAuthority` and a disposable local socket.

Each prompt now creates and persists a bridge-owned `turn:<request-id>` before any
runtime I/O. Runtime events, steer, and cancel carry that exact turn ID. A final
event clears the active turn; later events from it are rejected. Runtime calls occur
between a durable prepare phase and a durable completion/uncertain phase, outside
the controller mutation queue, so a slow prompt cannot delay cancellation or event
processing.

`EphemeralTestAuthority` is only a local test adapter: it creates random, one-use
proofs in process memory and writes no credential or identity state. Production must
provide an operator bootstrap that derives actor and conversation identity outside
the renderer/project, issues short-lived command proofs, and separately authenticates
the runtime identity. No production credential format or provider is assumed here.

`OperatorMainProcessCapabilityIssuer` and
`createOperatorMainProcessTransport` are the production bootstrap seam. The desktop
main process receives an already-verified `OperatorDesktopIdentity` and an
operator-owned proof exchange; it closes over both and accepts only action/binding
input from the renderer IPC adapter. It deliberately has no configuration-file,
environment-variable, or project-settings reader, so no renderer or project-supplied
identity can become trusted by accident.

`installHostOperatorBootstrap` is the matching desktop-host injection point. It
accepts only a host-created factory, rejects replacement, and defaults to an
unconfigured panel until installation. The OpenCode patch must call it from trusted
operator-managed startup code before extensions load; it intentionally provides no
project-file, renderer-message, environment, or credential-reading configuration
path. Tests reset this process-local seam only through its explicitly test-only API.

`CommanderMainProcessPanel` is the corresponding renderer-facing main-process
adapter. It accepts only panel text/actions, generates request IDs in main, and
delegates to an already bootstrapped transport. Its snapshots contain conversation
events but never capability proofs, endpoint configuration, actor identity, or
runtime credentials. The maintained OpenCode patch must instantiate it only from an
operator bootstrap; an absent bootstrap remains visibly `not-configured`.

Runtime events may optionally carry `OpenCodeMessageProvenance`: a runtime namespace,
project ID, exact `ses_` session ID, exact `msg_` message ID, and optional agent and
parent-session IDs. The bridge persists it with the Commander event and exposes it
only to continuation code by delivery ID; panel state does not project it. It is a
lookup reference, never an authorization grant. `OpenCodeSessionContinuation` calls
the normal authenticated OpenCode session endpoint for that exact reference and
marks the submitted input only with `{ fromCommander: true }` metadata. It adds no
credential, bypass, or LiteLLM routing rule. A missing, deleted, or inaccessible
reference fails explicitly; it never falls back to titles, agent names, or a
replacement session. A deterministic `msg_` input ID makes a restart retry use
OpenCode's ordinary durable admission/idempotency behavior.

`FileConversationStore` and `FileFutureTaskDeliveryStore` are single-operator durable
adapters; they atomically write replay metadata and delivery receipts with mode
`0600`. A scaled deployment must replace them with a transactional operator-owned
store. Their test doubles are deterministic only. `CapabilityVerifier` is likewise an adapter whose
implementation must validate audience, actor, conversation, action, request binding,
expiry, and replay atomically. This component refuses to derive any actor or
conversation identity from panel input.

Run the current dependency-free tests with:

```sh
npm test
```

The real cross-runtime FutureTasks check is opt-in because it starts a disposable
Kirei Compose service. It uses `ConfiguredGateway`, a real due-job worker, and an
ephemeral authenticated Node listener; no credential is written to disk. Start the
disposable service on a free loopback port, then run:

```sh
env BACKEND_PORT=59998 docker compose --project-name digitaltwin-final \
  --env-file .env.example -f compose.yml up -d backend-web
(cd commander/bridge && DIGITALTWIN_RUN_DOCKER_E2E=1 npm test)
```

On Docker Desktop the test reaches its temporary listener through
`host.docker.internal`. On a Linux CI runner, set
`DIGITALTWIN_BRIDGE_E2E_ORIGIN` to the runner-reachable listener origin. This is
backend-to-bridge transport coverage, not an Electron or production identity test.

When prepared inside the pinned OpenCode workspace, run strict TypeScript with:

```sh
bun --filter @digitaltwin/commander-bridge typecheck
```

The command uses Node 22 type stripping solely to run the test suite while the pinned
OpenCode checkout's TypeScript toolchain is being repaired. It is not a replacement
for the upstream `tsgo` check, which remains required before the maintained UI patch
or bridge adapter can pass the Gate 1 implementation evidence.

# Hermes Commander restoration plan

## Status

Proposed after the user clarified that Hermes, rather than an OpenCode session,
is the required Commander harness. This plan changes no running service,
profile, credentials, provider, dependency, or project-worker behavior.

## What was lost

Commit `182000d` removed the former `agent-runtime` Hermes profile, configuration,
and Herdr integration while introducing the FutureTasks-only path. The current
OpenCode implementation consequently uses a neutral OpenCode session as
Commander. That preserved the global UI, normal OpenCode workers, exact-session
continuation, and Kirei FutureTasks, but it did not implement the product
requirement for Commander-owned durable memory, skills, history, and learning
visibility.

Hermes should be restored as the Commander harness. It must not become a second
source of truth for Kirei schedules or project-worker sessions.

## Static evidence: installed Hermes and supported API

The installed launcher is `/Users/lr/.local/bin/hermes`; static inspection shows
it launches the local source checkout
`/Users/lr/.hermes/hermes-agent`. That checkout is at
`3f62bc534296ece8d89b94bd20ddad0fc34791d3`, described by Git as
`v0.21.4+canary.20261006T070224Z-730-g3f62bc5342`. This is an observation, not a
release pin or approval to use/update it. No Hermes command was run for this
inspection.

Its checked-in gateway source exposes a supported API-server contract:

| Need | Supported interface | Evidence |
| --- | --- | --- |
| Start/retry a Commander turn | `POST /v1/runs` with `input`, stable `session_id`, and `Idempotency-Key` | `gateway/platforms/api_server_runs.py:_handle_runs` |
| Durable conversation continuation | Repeat `POST /v1/runs` with the same `session_id`; the gateway resolves a live post-compression session and loads its stored history | `_handle_runs`, `_resolve_live_session_id` |
| Streaming and reconnect | `GET /v1/runs/{run_id}/events`, structured SSE with sequence replay through `Last-Event-ID` | `_handle_run_events` |
| Stop | `POST /v1/runs/{run_id}/stop` | `_handle_stop_run` |
| Steer active work | `POST /v1/runs/{run_id}/steer` with `input`/`message`/`text` | `_handle_steer_run` |
| Inspect a run | `GET /v1/runs/{run_id}` | `_handle_get_run` |
| Discover interface/version capability | `GET /v1/capabilities` | `gateway/platforms/api_server.py:_handle_capabilities` |
| Model inventory | `GET /api/model/options` (profile scoped; default `refresh=false`) | `hermes_cli/web_routers/models.py:get_model_options` |
| Set an already-configured model | `POST /api/model/set` | `hermes_cli/web_routers/models.py` |

The API-server capability table also advertises these routes in
`gateway/platforms/api_server.py`. It is bearer-authenticated when the configured
gateway requires it. The adapter must keep that bearer value outside the renderer,
Git, and Kirei records.

Official documentation independently confirms profile isolation, persistent
memory, session search, skills, and an API/gateway model; it does not make an
unbounded autonomous-learning policy safe or required.

- https://hermes-agent.nousresearch.com/docs/user-guide/profiles
- https://hermes-agent.nousresearch.com/docs/user-guide/features/memory
- https://hermes-agent.nousresearch.com/docs/user-guide/features/heartbeat
- https://github.com/NousResearch/hermes-agent/releases

## Deployment constraints

Local development and tests run directly on macOS under Overmind. Remote
deployments run the complete stack in Docker; Docker is not part of the local
test path. The later self-contained macOS application targets ARM64 only and
bundles the required Ruby, Python, and OpenCode runtimes. Packaging remains a
separate scope, and its final size must be measured rather than guessed.

## Smallest integration

Keep the maintained OpenCode Commander overlay and every ordinary OpenCode project
session. Replace only the overlay's Commander transport with a **thin local
Hermes adapter** hosted on the trusted OpenCode sidecar/plugin boundary; do not
add a separate general-purpose bridge service.

The adapter owns:

1. a Commander-only Hermes profile directory and one durable Hermes `session_id`;
2. `POST /v1/runs`, event SSE relay/replay, status, steer, and stop requests;
3. an opaque UI run identifier mapped to Hermes `run_id`, `session_id`, and
   idempotency key; and
4. compact, typed events for completed output, pending approval, and accepted
   memory/skill changes.

The renderer receives typed host events and never receives the Hermes bearer token
or filesystem/profile access. The native composer shell remains the UI surface;
its send/stop/steer transport moves from `context.session.prompt` to the adapter.
The model picker must load Hermes' configured model options through the adapter,
not reuse OpenCode's provider list. It may reuse native picker presentation only
after its data/selection contract is mapped and tested.

The existing `commander_continue_agent` plugin stays unchanged for project
workers: it resumes only exact OpenCode sessions with Commander provenance.
Hermes Commander delegation invokes that plugin only for explicit worker work;
the plugin does not make Hermes a project-worker harness.

Kirei remains the sole durable scheduler. A due FutureTask calls the adapter with
a delivery key; the adapter submits the stored check-in to the Hermes Commander
session using an idempotency key derived from that delivery key, then records the
Hermes run/result receipt. Hermes heartbeat/cron are not used for Kirei-owned
commitments.

## Learning and security boundary

Hermes profile memory, history, session search, and skills are Commander-local.
The first adapter must surface compact learning events only after Hermes reports a
memory or skill write. It must not mirror transcripts into Kirei or create a new
homegrown memory subsystem.

No mandatory approval policy is assumed for memory. Before enabling skill writes,
separately define the Hermes toolset/terminal permissions, profile filesystem
scope, and whether skill writes are staged or automatic. Those are execution
security controls, not a substitute for the user's desired learning behavior.

## Bounded implementation order and acceptance checks

1. **Project-local, no-provider probe.** Create an ignored profile under
   `local/hermes/commander-profile` only after approval, with `HERMES_HOME` and
   temporary paths inside `local/`. Start the gateway bound to loopback with an
   adapter-owned test token. Verify `/v1/capabilities`, `/v1/health`, and the
   advertised route table. Do not select a model or send a prompt.
2. **Adapter contract test.** Against a fixture/fake API server, prove stable
   session submission, idempotent retry, SSE sequence replay, status, steer,
   stop, bearer isolation, and rejection of unknown run/session references.
3. **UI transport swap.** Feed adapter events into the existing Commander host;
   retain overlay geometry, native composer keyboard behavior, global access, and
   project-session non-interference. Verify no OpenCode Commander neutral-session
   prompt is issued.
4. **Hermes lifecycle acceptance.** With an existing user-approved provider only,
   prove one real Commander prompt streams, stop and steer work, restart recovery
   preserves the Hermes conversation, and a repeat prompt uses the same session.
   Record the actual selected Hermes model when the runtime reports it.
5. **FutureTask delivery.** Prove one Kirei due delivery is deduplicated into the
   same Hermes session and reconciles an interrupted delivery without starting
   project work automatically.
6. **Learning visibility.** Prove an actual Hermes memory/skill event appears as
   a compact Commander item without transcript exposure. Exercise skill execution
   only after the separate tool-permission decision is approved.

## Decisions still required

- Which released Hermes version to pin after the no-provider capability probe.
- The Commander profile's allowed toolsets/terminal backend and filesystem scope.
- The desired skill-execution posture (automatic or staged) before skills can
  modify files. This is separate from keeping durable Commander memory.

No provider choice, credentials, paid request, or full runtime migration is needed
to make these decisions or complete the first two validation slices.

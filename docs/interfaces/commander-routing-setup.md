# Bounded Commander routing: setup and acceptance

Current commands below match the installed implementation.

Commander runs through Hermes. Runtime packages the latest supported Hermes stable release during
its normal image build. Hermes provider setup remains private operator configuration and is not
authenticated or validated by this repository.

## Feature boundary

Given one already mapped project and healthy bound Writer conversation, a verified human can add
instructions in Commander chat. MCP reads authoritative workflows and accessible recent task context,
proposes a cited target, and Kirei checks that evidence before queuing the same Writer ID/generation.
Ambiguity asks for clarification. Review/pause retains instructions until a writing phase resumes.
Startup and credential renewal keep the same target pending; they do not create replacement sessions.

Lost effect receipts now have bounded recovery:

| Exact human command in Commander chat | Evidence checked; no external action replayed |
| --- | --- |
| `@agent recover-followup ID delivered` or `discard` | Original human, destination membership, no live send lease, exact settled Writer conversation/generation. This records a human outcome, not an automatic socket receipt. Discard releases later queued instructions; a fresh human instruction is needed for any new send. |
| `@agent recover-start REQUEST_ID THREAD_ID` | Original human; actual bot/channel/root/title/request correlation, undeleted root, no live creation lease. Continue against that root without posting another. |
| `@agent recover-session OPERATION_ID PANE_ID` | Original workflow human (or initial Commander-request human), latest generation, no live effect lease. Start recovery verifies exact alias/cwd/CLI/conversation and credential digest; stop recovery requires authoritative unfiltered pane inventory proving absence. No start/close repeat. |
| `@agent recover-commander REQUEST_ID` | Original human, settled same Commander and no unresolved associated workflow/session/review effects. Complete the old request and unblock later requests; no prompt replay. |

IDs appear in queue/reservation receipts. Recovery is not proof of a send when the user selects
`delivered`; the audit labels that as human confirmation. A missing conversation/receipt remains
blocked rather than guessing, rebinding to a new generation or creating a duplicate resource.
A valid exact review callback also reconciles an uncertain review prompt after its lease expires:
role capability, runtime identity, frozen target, clean Git diff and append-only metadata are verified.

New project enrollment through MCP is a separate convenience: MCP has no enroll tool, but the existing backend
`Projects::Enroll` service validates registration of a local repository and verified human channel.
Existing mapped projects need no enrollment change for follow-ups. Clone/private GitHub creation
is not required for this feature. Verified PR-delivery/`done` is also separate: follow-ups work in
writing/review phases; PR delivery only determines when later `finish` can archive completed work.

## Minimum operator setup (no secret values in Git or messages)

1. Run reviewed local backend/Runtime/chat images with migrations 001-008. Worker and Runtime
   share `/workspace` and `/run/herdr` as UID 10001; only Runtime has provider home state. Web
   has neither Git workspaces nor the Herdr socket. Build clients with the checksum staging script.
2. Provide existing authenticated chat identities through read-only token-file mounts. Listener
   needs `MATTERMOST_URL`, `MATTERMOST_LISTENER_TOKEN_FILE`, `MATTERMOST_LOCAL_BOT_IDS`,
   `MATTERMOST_CHANNEL_IDS` (including Commander and project), and `COMMANDER_CHANNEL_ID`.
   Worker additionally needs `MATTERMOST_WORKER_TOKEN_FILE`, `MATTERMOST_AGENT_TOKEN_FILE`,
   both corresponding `*_BOT_ID` values, and the same local-bot IDs. Web's request-bound MCP
   services need the listener/Worker token-file references, Worker bot ID and chat/local-bot settings
   for authoritative REST checks. Optional peers use `MATTERMOST_PEER_BOT_IDS`. No bot token
   goes to Runtime. Activate only the disposable chat-validation listener/worker transport for acceptance;
   `CHAT_VALIDATION_MODE=1` does not enable Herdr effects.
3. Supply `ROLE_CONFIG_FILE` to web and worker: a trusted Commander entry; Writer/Reviewer
   entries are additionally required when creating workflows or running review. Each entry contains `cli`, `provider`, `model`, `family`, `launch_args` (string array). The Commander entry must use
   `"cli": "hermes"`. Writer/Reviewer must differ in provider
   and family. Use the actual already authorized models/login setup in Runtime; do not pass provider
   credentials as launch arguments. The persistent Commander directory is `/workspace/commander`.
   Hermes is the harness; it does not fix Commander to Gemini or any other model. Its optional xAI Grok provider is
   supported natively as `provider: xai` (alias `grok`) with an existing `XAI_API_KEY`, or as
   `provider: xai-oauth` (alias `grok-oauth`) after an operator-run `hermes model`/`hermes auth add
   xai-oauth` login. Select the actual Grok model in the private Hermes profile or interactive
   model picker; do not add a key, OAuth token, model default, or provider value to Git, launch
   arguments, logs, or this setup file. Gemini remains an optional Hermes provider, not a default.
   Runtime also packages the official xAI Grok Build CLI for a separately configured Writer or
   Reviewer role (`"cli": "grok"`); it is not a Commander replacement or a Hermes provider
   setting. Grok Build accepts an operator-provided `XAI_API_KEY` or its official login outside
   Git. Its default Runtime config disables background self-updates. No role is enabled merely by
   installing the binary; Kirei still verifies the configured role and all workflow authorization.
4. Retain a verified `projects` row binding the project channel to its repository slug/origin and
   `/workspace/repos/owner/repo`. Repository origin must match; branches/worktrees are verified.
   For existing-session acceptance, bind Writer's actual Herdr pane, alias, cwd, CLI, opaque
   `agent_session`, generation and runtime-only token digest/file. Never invent these values.
5. Set `DIGITALTWIN_CALLBACK_URL=http://backend-web:3000` for the worker's session environment.
   Herdr workspace creation supplies the generated session-token file, generation and current
  Commander-request token-file path; the operator does not create or transmit their values.
6. Runtime initializes `/workspace/commander/.hermes/config.yaml` when it does not exist. It registers
   the private Kirei MCP server below without replacing an existing Hermes profile or provider configuration:

```yaml
mcp_servers:
   digitaltwin:
     command: /usr/local/bin/digitaltwin-mcp
     args: []
     env:
       DIGITALTWIN_CALLBACK_URL: ${DIGITALTWIN_CALLBACK_URL}
       DIGITALTWIN_COMMANDER_REQUEST_TOKEN_FILE: ${DIGITALTWIN_COMMANDER_REQUEST_TOKEN_FILE}
     tools:
       include:
         - list_projects
         - list_workflows
         - read_context
         - workflow_status
         - start_workflow
         - send_prompt
         - workflow_control
```

The explicit environment passes a capability-file path, not a token. Keep other Hermes permissions
unchanged. The tool allowlist is the typed Kirei manifest. Runtime tests check profile creation,
restart persistence, and the packaged MCP bridge. They do not prove authenticated Hermes startup,
tool discovery, or tool calls.

## Minimum evidence before enabling dispatch

Capture sanitized artifact/version/schema identities, state transitions and opaque correlations:

- Actual chat human/bot identities, both memberships, ordinary Commander posts, project root/replies,
  and reconnect/refetch behavior on the selected server.
- Actual Hermes start through Herdr, exact conversation identity and settled/readiness fields;
  installed MCP initialize/list/read-context/tool-call for the verified human request. Wrong or
  expired capabilities must fail; no provider value/token appears in evidence.
- Actual Writer start/get/prompt/settled on the same conversation and a source-thread callback.
  If enabling workflow creation/review as well, verify the configured Reviewer start/settled,
  diversity and review callback. Existing-workflow follow-ups do not require PR delivery or cloning.
- One Commander instruction, one additional instruction to the same Writer, an ambiguous request,
  review-lock queue/release and concurrent follow-ups; show IDs/generations did not change and
  acknowledgments distinguish queued, delivered and human-reconciled outcomes.

Then review a bounded policy-code change and re-arm only unsent evidence-blocked jobs after
source/state revalidation. `Policy#dispatch_allowed?` is intentionally hard-coded false: there is
no ENV switch, and setup alone cannot enable this branch. No authenticated/provider run has been
performed by this task. Obtain authorization for any acceptance run that could consume paid usage.

## Review and CI

Independent read-only review covered the expanded routing/lifecycle/review/MCP code and its
packaging, not only the initial routing increment. Reviewer independently ran 17 root/provenance
checks. Backend final check passed 132 examples, 87 lint-clean files and shared-contract typing. Actual Herdr
pane.list verified created-pane presence and closed-pane absence; no CLI started. Backend/Herdr/Runtime
fixture checks were run by the implementer. The PR's final-head
GitHub check rollup is empty; the repository has no `.github/workflows` configuration. Local
checks are reported as local evidence, not green hosted CI or authenticated acceptance.

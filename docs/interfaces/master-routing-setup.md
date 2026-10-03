# Bounded Commander routing: setup and acceptance

Gemini was already the specified Commander default on main `f01b846` (§17 of the specification).
This feature did not select another runtime or configure/authenticate Gemini. Runtime packages
Gemini CLI 0.62.0; the actual operator role/model/launch profile remains to be supplied and validated.

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
| `@agent recover-session OPERATION_ID PANE_ID` | Original workflow human (or initial Master-request human), latest generation, no live effect lease. Start recovery verifies exact alias/cwd/CLI/conversation and credential digest; stop recovery requires authoritative unfiltered pane inventory proving absence. No start/close repeat. |
| `@agent recover-master REQUEST_ID` | Original human, settled same Commander (`controller` internally) and no unresolved associated workflow/session/review effects. Complete the old request and unblock later requests; no prompt replay. |

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
   `MATTERMOST_CHANNEL_IDS` (including Commander and project), and `MASTER_CHANNEL_ID`.
   Worker additionally needs `MATTERMOST_WORKER_TOKEN_FILE`, `MATTERMOST_AGENT_TOKEN_FILE`,
   both corresponding `*_BOT_ID` values, and the same local-bot IDs. Web's request-bound MCP
   services need the listener/Worker token-file references, Worker bot ID and chat/local-bot settings
   for authoritative REST checks. Optional peers use `MATTERMOST_PEER_BOT_IDS`. No bot token
   goes to Runtime. Activate only the disposable chat-validation listener/worker transport for acceptance;
   `CHAT_VALIDATION_MODE=1` does not enable Herdr effects.
3. Supply `ROLE_CONFIG_FILE` to web and worker: a trusted controller entry; Writer/Reviewer
   entries are additionally required when creating workflows or running review. Each entry contains `cli`, `provider`, `model`, `family`, `launch_args` (string array). Controller remains
   Gemini unless the operator explicitly chooses otherwise. Writer/Reviewer must differ in provider
   and family. Use the actual already authorized models/login setup in Runtime; do not pass provider
   credentials as launch arguments. The neutral Commander directory is `/home/runtime`.
4. Retain a verified `projects` row binding the project channel to its repository slug/origin and
   `/workspace/repos/owner/repo`. Repository origin must match; branches/worktrees are verified.
   For existing-session acceptance, bind Writer's actual Herdr pane, alias, cwd, CLI, opaque
   `agent_session`, generation and runtime-only token digest/file. Never invent these values.
5. Set `DIGITALTWIN_CALLBACK_URL=http://backend-web:3000` for the worker's session environment.
   Herdr workspace creation supplies the generated session-token file, generation and current
  Commander-request token-file path; the operator does not create or transmit their values.
6. In the operator-owned Runtime Gemini user settings (`/home/runtime/.gemini/settings.json`),
   merge this server entry without replacing other settings or login state:

```json
{
  "mcpServers": {
    "digitaltwin": {
      "command": "/usr/local/bin/digitaltwin-mcp",
      "env": {
        "DIGITALTWIN_CALLBACK_URL": "$DIGITALTWIN_CALLBACK_URL",
        "DIGITALTWIN_MASTER_REQUEST_TOKEN_FILE": "$DIGITALTWIN_MASTER_REQUEST_TOKEN_FILE"
      }
    }
  }
}
```

Gemini sanitizes inherited `*TOKEN*` variables; this explicit `env` passes the file path, not a token.
Approve only the reviewed Digitaltwin MCP tool policy in the operator's existing CLI confirmation
settings so normal typed calls can proceed. Keep other permissions unchanged. The pinned package's
`mcpServers` shape was inspected offline; the current [official MCP configuration documentation](https://geminicli.com/docs/tools/mcp-server/)
confirms command/env expansion and explicit environment overrides. Configuration inspection is
not proof that authenticated Gemini startup, tool discovery and tools/call succeed.

## Minimum evidence before enabling dispatch

Capture sanitized artifact/version/schema identities, state transitions and opaque correlations:

- Actual chat human/bot identities, both memberships, ordinary Commander posts, project root/replies,
  and reconnect/refetch behavior on the selected server.
- Actual Gemini start through Herdr, exact conversation identity and settled/readiness fields;
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

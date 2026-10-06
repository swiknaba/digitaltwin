# Simplified setup and task intake

Status: proposed for product review.

## Purpose

Digitaltwin is a vendor-neutral workspace for small engineering teams.
After authentication, people start work with a Git URL and task.

Commander, through Hermes, is central. People can also control workers through chat or CLI.
Work needs no server administration.

## Task-first experience

### First use

The person authenticates the required harnesses. Digitaltwin creates and verifies needed identities and mappings.
People do not manually create bots, channels, role files, model catalogues, checkouts, or enrollment mappings.

### Start, continue, or direct work

In Commander, a person can say: “Work on `https://git.example/team/api`: add request tracing.”
Digitaltwin resolves the repository with installation Git access, prepares the task workspace, starts work, and reports its target and state. No channel or start command is needed.

Missing Git access requests authentication and retains the task for retry. Follow-ups keep the matching task, repository, working directory, and healthy session when safe.
Digitaltwin asks only to distinguish tasks; it never creates replacement work or silently changes a running session's directory.

Direct worker chat and CLI follow the same rules without an intervening Commander interaction, new client, or server shell.

### Channels, repositories, and working directories

Each channel has one purpose, such as a task, project, incident, or team topic. It can have an optional default repository, not a fixed boundary.

An explicit repository or Git URL overrides the default. For new work without either, Digitaltwin uses the default or asks a short target question.

Digitaltwin resolves the selected repository to a managed checkout and concrete task directory; people do not supply paths.
Parallel work uses separate Git worktrees for conflict control, not repository isolation. Cross-repository work is allowed, with each worker's target visible.

### Observe and act

A person can ask Commander to observe a named condition: “Watch CI for this pull request. If its current head is green, merge it. If red, fix it, push, and check again.” The task remains open and retains the repository, pull request, current head, requesting person, and allowed action.

A bounded check or supported event wakes the task without holding a worker idle. Green applies only to the exact current head; a fix creates a new head and requires a new check.
Merge still needs the task's authorization and review constraints. On failure, the task diagnoses and fixes within its authorization, or reports a blocker.

The task shows that it is waiting, what it is watching, and its next check. It ends as merged, fixed, or blocked. Restart retains the wait state; an uncertain external effect is reconciled instead of repeated.

## Shared boundary and execution

One installation serves one developer or mutually trusting team. Its granted repositories are available inside the shared boundary. Different repository rights use separate installations.

Engineers and agents have a flexible shell for scripts, builds, tests, and debugging. They can use approved APIs, such as Sentry or Loki, when enabled. Normal commands need no per-command approval.

The environment enforces limits outside prompts. It blocks host administration, Docker-daemon access, privileged execution, and outside-boundary resources, then reports the block clearly.

Operators configure installation access and controls; engineers use normal product interfaces; agents cannot change the boundary.
An optional future local worker may use a developer machine when required. It uses that account's trust boundary and keeps the managed worker as default.

## Choices, status, and scope

Digitaltwin handles repository resolution, workspace preparation, task context, and safe reuse. It asks only for missing authentication, genuine ambiguity, an explicit harness or model choice, collaboration changes, or an existing destructive-action confirmation.

Each task shows: **Setting up**, **Ready**, **Working**, **Waiting**, **Needs you**, **Delivered**, or **Uncertain**.
Errors name the task or repository, give the safe next action, never silently substitute a request, and never retry an uncertain effect.

This scope adds no connector suites, platform layer, VM-per-command model, hostile-tenant claim, provider-login automation, or OpenClaw migration.
It does not relax existing workflow or destructive-action rules.

## Acceptance scenarios

1. A new user authenticates and submits work without manual bot, channel, role-file, checkout, or enrollment setup.
2. A Git URL and task in Commander create usable context and a task directory without a manual start mention.
3. A follow-up keeps its task repository and directory; an explicit URL overrides a channel default.
4. Direct worker chat or CLI follows the same rules without a Commander interaction.
5. Trusted teammates work across two repositories in one installation, with each target visible.
6. Missing Git credentials request setup and do not start work.
7. Normal scripts and approved APIs need no repeated confirmation; outside-boundary actions are denied without duplicate work.
8. A CI-watch task retains its PR and head while waiting; it merges only an authorized green current head, or fixes and rechecks a failing one.

## Current state and supporting note

This is future behavior. The current local activation runbook remains unchanged until implementation is reviewed and verified.
The related authenticated-harness draft removes normal role-file and model-metadata setup; this specification assumes that direction without implementing it.

The Runtime pins Hermes `v2026.9.24`. Hermes has native goal, heartbeat, and cron facilities for waiting tasks, but the current Digitaltwin profile exposes no CI, pull-request, merge, or observation tool. This behavior should use a supported Hermes wait facility after Digitaltwin binds verified targets and authorization, not a new scheduling platform.

The repository documents a non-root Runtime without a Docker socket, privileged mode, or host-root mount. It also states that a shared Runtime is not a hostile-tenant boundary.
Docker's guidance supports enforcing boundaries outside prompts. OpenClaw and Hermes document comparable trust and sandbox concepts; this is neither a uniqueness nor migration claim.

- [Docker Engine security](https://docs.docker.com/engine/security/)
- [OpenClaw security trust model](https://docs.openclaw.ai/gateway/security/trust-model)
- [Hermes security guide](https://hermes-agent.nousresearch.com/docs/user-guide/security)
- [Hermes persistent goals](https://hermes-agent.nousresearch.com/docs/user-guide/features/goals)
- [Hermes heartbeat](https://hermes-agent.nousresearch.com/docs/user-guide/features/heartbeat)

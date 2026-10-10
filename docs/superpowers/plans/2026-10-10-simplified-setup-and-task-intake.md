# Simplified Setup and Task Intake Implementation Plan

**Status:** Draft for product review. This plan does not approve dispatch, provider access, CI mutations, or deployment.

**Goal:** Let an authenticated person start or continue work with a repository URL and task, while Digitaltwin resolves the target, prepares a safe workspace, and reports a useful task state.

**Architecture:** Keep Kirei authoritative for verified actors, routing, workflow/review gates, durable state, and uncertain-effect recovery. Separate repositories from channel purpose/defaults. Route Commander, direct chat, and CLI requests through the same typed task-intake and repository-resolution services. Keep managed Herdr sessions and per-task Git worktrees; enforce the shared installation boundary in Runtime and its host configuration, not in agent prompts.

**Spec:** [`docs/superpowers/specs/2026-10-06-simplified-setup-and-task-intake-design.md`](../specs/2026-10-06-simplified-setup-and-task-intake-design.md), introduced by commit `771b9de79c58ede4f2bd8e41af2e939a92202d07` (`docs: specify simplified Digitaltwin setup`). The spec is proposed for product review and describes future behavior.

## Current Code and Constraints

- `integration-backend/app/domains/projects/entities/project.rb` and migration `002_projects.rb` bind one channel to one repository. `Services::Projects::Enroll` and `Services::Projects::ResolveRepository` assume an operator-prepared checkout.
- `Services::Commander::Tools#start` takes a `project_id` and title. `Services::Workflows::RequestStart`, `Provision`, and `Projects::PrepareWorktree` already provide durable, verified workflow creation and a per-workflow worktree. `RouteFollowup` already grounds task selection and reuses only the matching active Writer session.
- `Services::Configuration` still reads `ROLE_CONFIG_FILE` and local activation hashes it. The authenticated-harness setup document is a requirements draft, not an implemented or verified contract.
- Workflow review, human approval, session identity, job leases, and uncertain external effects are established boundaries. Preserve them; task-first intake does not waive them.
- The latest checked-in migration is `010_remove_commander_memory.rb`. Coordinate the next migration number with the Kirei owner. Preserve database ownership: Kirei and Mattermost continue using separate databases and roles.
- Runtime is non-root and has no Docker socket or privileged mode. The spec's shared installation is for one developer or mutually trusting team, not hostile-tenant isolation. Do not add a platform layer, connector suite, per-command approval loop, provider-login automation, or OpenClaw migration.

## Decisions and Evidence Required Before Dependent Work

1. Review and accept the proposed product behavior, including whether Commander is the default entry point and what “authenticate the required harnesses” means for this release. Resolve this with the related authenticated-harness draft before replacing the role-file contract.
2. Select and prove the supported installation Git-auth mechanism, grant/revoke flow, URL-to-repository identity rules, and safe credential storage for the chosen host(s). Do not infer provider behavior from documentation or ship credentials in Git or images.
3. Select the supported direct-chat and CLI entry points and their source-authentication contract. They must call the common intake path and must not require a Commander interaction or server shell.
4. Select the first observation provider and supported CI/PR wake-up mechanism. The current Commander MCP profile has no CI, PR, merge, or observation tool. Verify the pinned Hermes wait facility against the installed Runtime before depending on it; the spec's supporting note is not live compatibility evidence.
5. Confirm which existing workflow approval/review rules govern a requested merge, and whether the initial observe-and-act release is limited to one host/provider. Keep destructive-action confirmation rules in force.

These decisions block the relevant implementation tasks below; synthetic tests and documentation inspection do not clear live authentication, CLI, event, or MCP gates.

## Task 1: Separate Repository Identity from Channel Purpose

**Files:**

- Modify: `integration-backend/app/domains/projects/` (currently repository identity, project directory, and workspace paths)
- Modify: `integration-backend/app/services/projects/` (`Enroll`, `ResolveRepository`, `PrepareWorktree`)
- Modify: `integration-backend/app/domains/workflows/` request/workflow DTOs and records
- Modify: `integration-backend/db/migrate/` (append after the current latest migration; coordinate number)
- Test: `integration-backend/spec/domains/projects_spec.rb`, `integration-backend/spec/domains/workflows/workflows_spec.rb`, and focused service specs under `integration-backend/spec/services/`

**Interfaces:** Add typed repository and optional channel-default-repository values. A workflow records its resolved repository identity and task directory independently of the channel. Explicit task repository wins over the channel default; absent both, intake returns a short target clarification.

- [ ] Add a forward-compatible schema path for repositories and optional channel defaults. Backfill existing `projects` rows and workflow repository references without deleting or reinterpreting existing workflow data.
- [ ] Preserve existing channel/project mappings through a compatibility period; document when old enroll/resolve entry points stop accepting new writes. Do not drop columns/tables until upgrade and rollback behavior is decided against supported deployed schemas.
- [ ] Make repository resolution verify the installation grant, canonical remote identity, checkout containment, and the workflow worktree's common Git directory. Keep task paths server-derived.
- [ ] Test fresh install, upgrade with existing projects/workflows, idempotent backfill, explicit URL override, default lookup, unknown/revoked grants, cross-repository work, and invalid/out-of-root paths.

**Done:** Two repositories can be available to one channel/team; a channel can have no default or an optional default; an explicit URL always selects the requested granted repository; legacy rows remain usable after upgrade.

## Task 2: Authenticate Setup and Remove Manual Enrollment Prerequisites

**Files:**

- Modify: `integration-backend/app/services/configuration.rb`, `integration-backend/app/services/composition.rb`
- Modify: Runtime harness inventory/authentication boundary under `agent-runtime/` and its packaged client contract in `agent-runtime/contracts/kirei-clients.json`
- Modify: `integration-backend/app/domains/sessions/` configuration/availability DTOs and selection policy
- Modify: `integration-backend/app/domains/workflows/dto/role_file.rb`, `role_config.rb`, and `integration-backend/app/domains/workflows/dto/local_dispatch_activation.rb` only after the authenticated-harness contract is accepted
- Test: corresponding backend configuration, session, workflow policy, and Runtime offline image/contract checks

**Interfaces:** Runtime reports typed harness availability without returning credentials. Operators authenticate harnesses and grant repositories through the reviewed installation setup; normal users do not create bots, channels, role files, model catalogues, checkouts, or enrollment mappings.

- [ ] Implement only the selected supported harness-auth detection. Distinguish authenticated, unauthenticated, and unknown; executable presence or credential-file presence alone is not proof. Do not prompt a provider merely to discover authentication.
- [ ] Select Writer/Reviewer from available harnesses using the accepted policy; honor explicit per-task choices, report unavailable choices without substitution, persist the choice for recovery, and retain review diversity/approval constraints unless a reviewed decision changes them.
- [ ] Replace the role-file/local activation hash dependency with an explicit typed readiness result only after runtime and backend checks agree. Keep all effects fail-closed when authentication or identity mappings are missing.
- [ ] Store credentials only in private operator-managed storage. Verify no provider login state, signing material, or secrets enter source, image layers, fixtures, or logs.
- [ ] Test missing, unknown, and revoked authentication; successful detection; explicit harness/model selection; unavailable selection; restart persistence; and no provider prompt during detection.

**Done:** A new user can complete supported authentication and submit work without manual bot, channel, role-file, model-metadata, checkout, or enrollment setup. Operator controls remain separate from normal engineering use.

## Task 3: Make Task-First Intake Common to Commander, Chat, and CLI

**Files:**

- Modify: `integration-backend/app/services/commander/tools.rb` and its `tool_name.rb`, `tool_field.rb`, `tool_arguments.rb`, and `start_receipt.rb` DTOs
- Modify: `integration-backend/app/adapters/mcp/http_tools.rb` and Commander manifest/HTTP translation
- Extract or extend: `integration-backend/app/services/workflows/request_start.rb`, `start_existing.rb`, and typed task-intake/repository-resolution DTOs
- Modify: `integration-backend/app/services/inbound/`, `integration-backend/app/services/commands/`, and CLI client entry points as required by the decision in item 3 above
- Test: existing `integration-backend/spec/domains/commander_tools_spec.rb`, `integration-backend/spec/services/commands/`, `integration-backend/spec/adapters/mcp/`, and new focused workflow/Commander service specs under `integration-backend/spec/services/`, plus `tests/` cross-service contracts

**Interfaces:** Replace the start request's required `project_id` with task text and an optional repository URL/identity. The shared intake service returns a typed accepted, needs-authentication, needs-target, needs-clarification, or rejected result tied to one durable request. Existing workflow approval and destructive-action tools remain separate.

- [ ] Parse a Git URL plus task from Commander input, resolve it against installation grants, and call the same application service used by direct worker chat and CLI. Preserve verified human source, request idempotency, and durable job receipt.
- [ ] Retain a task that lacks Git access in a retryable “Needs you”/authentication state; do not create a workflow, worktree, or session until access is verified. Resume that exact request after authentication.
- [ ] Match follow-ups against verified task/repository/session context. Reuse only the same healthy session and directory; ask one concise clarification when multiple tasks are plausible. Never create replacement work or change a running session's directory silently.
- [ ] Keep repository URL and target visible in acknowledgements and status. Errors identify the task/repository and a safe next step.
- [ ] Test no manual start mention, duplicate/replayed intake, missing auth retention and retry, ambiguous tasks, direct chat and CLI convergence, follow-up reuse, and explicit URL precedence.

**Done:** Commander can start work from “repository URL: task”; direct chat and CLI achieve equivalent behavior through the same intake service without Commander or server shell mediation.

## Task 4: Prepare Managed Task Directories and Enforce the Shared Boundary

**Files:**

- Modify: `integration-backend/app/services/projects/prepare_worktree.rb`, `resolve_repository.rb`, and `integration-backend/app/domains/projects/workspace_paths.rb`
- Modify: `integration-backend/app/services/workflows/provision.rb`, `reconcile_start.rb`, `dispatch_phase_prompt.rb`, `integration-backend/app/services/commander/deliver_followup.rb`
- Modify: `agent-runtime/Dockerfile`, `agent-runtime/entrypoint.sh`, Runtime configuration/contracts, `compose.yml`, and `.env.example` only for reviewed enforcement controls
- Test: Git/worktree/project/workflow unit specs, Runtime image security checks, `tests/` Compose and cross-service acceptance

**Interfaces:** The server chooses a concrete directory under managed repository/worktree roots. Parallel workflows receive separate Git worktrees for conflict control. The installation grant is the shared repository boundary; a channel is organizational context, not an access boundary.

- [ ] Extend provisioning to clone or reuse only the verified installation-managed checkout, then create/revalidate a task-specific worktree and record its concrete path before session launch.
- [ ] Validate all paths and Git remotes on initial setup and recovery. Reject traversal, mismatched remotes, out-of-grant repositories, and sessions whose live cwd differs from the task record.
- [ ] Enforce the reviewed shell/resource limits outside prompts: non-root execution; no host administration, Docker socket, or privileged execution; no access outside the installation boundary. Report denials clearly and prevent duplicate effects after uncertain results.
- [ ] Permit normal scripts and approved APIs without per-command confirmation. Configure approved APIs explicitly; do not add a generic connector suite or VM-per-command architecture.
- [ ] Test two trusted users/repositories in one installation, separate parallel worktrees, visible target paths, denied boundary escapes, approved API use, normal shell commands, changed grants, recovery, and uncertain external actions.

**Done:** Users never supply filesystem paths; each worker sees its resolved repository and task directory; enforcement and denials are exercised in the Runtime, not represented only in instructions.

## Task 5: Project Simple Task Status without Weakening Workflow Gates

**Files:**

- Modify: `integration-backend/app/domains/workflows/dto/phase.rb` only if new durable distinctions are required; prefer a typed status projection in `integration-backend/app/services/commander/`
- Modify: `integration-backend/app/services/commander/workflow_status.rb` and status DTOs
- Modify: `integration-backend/app/domains/workflows/entities/workflow.rb`, workflow records, and a forward migration only for durable waits/reasons not represented by existing state
- Modify: status delivery and any user-facing local runbook after implementation evidence is accepted
- Test: workflow/status/recovery and chat/Commander status specs

**Interfaces:** Display **Setting up**, **Ready**, **Working**, **Waiting**, **Needs you**, **Delivered**, or **Uncertain** as a typed projection of verified workflow/session/request state. Keep detailed spec/plan/review/approval phases internally and externally available where useful; the display status must not advance or bypass those gates.

- [ ] Define an exhaustive mapping from queued/provisioning, available/idle, active, waiting, authentication/clarification blockers, delivered, and uncertain records to the seven labels. Include the watched condition and next-check time for waits.
- [ ] Make task/repository target and safe next action present in every error/status response. Do not describe queued, received, or unverified work as delivered.
- [ ] Persist only state needed for restart and reconciliation. Add a migration only for state that cannot be derived; preserve current workflow rows and old-phase behavior.
- [ ] Test every status mapping, blocked/uncertain distinction, missing runtime observations, restart recovery, and no status transition that changes review or approval state.

**Done:** Every task has one honest user-facing status, with existing workflow and destructive-action rules unchanged.

## Task 6: Add Durable Observe-and-Act for One Verified CI/PR Path

**Gate:** Tasks 1–5 plus decision/evidence items 4–5 must pass. Do not start integration against an assumed Hermes API or unselected provider.

**Files:**

- Modify: `integration-backend/app/domains/workflows/` typed wait/observation records and workflow lifecycle
- Modify: `integration-backend/app/services/commander/` tools/status and worker wake/reconciliation services
- Modify: `integration-backend/app/adapters/` for the one selected CI/PR API and event or bounded-check adapter
- Modify: existing `integration-backend/app/platform/jobs/` only for durable wake/check jobs; add no scheduling platform
- Modify: `commander/AGENTS.md` and Runtime Hermes profile only to expose verified, narrowly scoped operations
- Test: adapter contract fixtures, workflow wait/recovery specs, authorization/review specs, cross-service CI-watch acceptance

**Interfaces:** A wait binds the requesting human, repository, PR, exact current head, authorized action, condition, and next check. Wake via one supported event or bounded check and Hermes' verified native wait facility. Kirei remains authoritative for authorization, workflow state, idempotency, and reconciliation.

- [ ] Add observation only for the selected provider and supported operation. Do not expose arbitrary shell, repository, or merge tools through Commander MCP.
- [ ] Persist waiting state and the full target/action binding before sleeping. A restart restores the wait; an uncertain merge/push is reconciled from remote evidence and never blindly repeated.
- [ ] Treat green as valid only for the exact recorded current head. If a fix/push creates another head, require a fresh check before merge.
- [ ] Apply existing authorization, review constraints, and required destructive-operation confirmation. On failure, either diagnose/fix within the task authorization or report a blocker.
- [ ] Test green exact head, stale green head, red then fixed new head and recheck, unauthorized merge, duplicate wake, lost response reconciliation, restart while waiting, and blocked provider access.

**Done:** A task visibly waits on a named condition, survives restart, and ends as merged, fixed, or blocked without duplicate or stale-head effects.

## Task 7: Acceptance, Runbook Transition, and Independent Review

**Files:**

- Modify: `tests/`, `scripts/` and their READMEs for automated acceptance/evidence
- Update only after verified release: `tests/local-human-runbook.md`, `integration-backend/README.md`, `agent-runtime/README.md`, and relevant interface docs
- Preserve: `docs/interfaces/local-commander-activation.md` and the current local activation runbook until the new path is reviewed and verified

- [ ] Cover the spec's eight acceptance scenarios end-to-end with synthetic fixtures where possible; label authenticated provider, CLI, event, and operator checks separately.
- [ ] Run component checks per component instructions, `integration-backend/bin/check`, whole-project Sorbet and RuboCop, root acceptance/full-stack checks, and Compose configuration on the final integrated revision. Record exact commands/results and unresolved gates.
- [ ] Complete a separate review against the spec and current workflow/review/uncertain-effect boundaries. Confirm migration upgrade behavior with existing project/workflow rows and legacy client behavior.
- [ ] Update setup instructions only when the implemented, reviewed behavior is verified. Keep manual activation steps for any still-unverified path.

**Done:** All eight spec scenarios are evidenced; claims distinguish synthetic from live/operator evidence; no provider login, deployment, or release activation is implied by this plan.

## Review Focus

1. Missing or revoked Git access must retain the same task request and must not clone, create a worktree, or start a session.
2. An explicit URL overrides the channel default; a channel has one purpose but is not a repository or permission boundary.
3. Two plausible follow-up targets require clarification before action; a matching healthy session keeps its repository and cwd.
4. A human/team member cannot use another installation's repository rights. The shared boundary is not described as hostile-tenant isolation.
5. Task status is derived from verified durable state; uncertain external effects remain uncertain until reconciled.
6. A CI result for an old head never authorizes a merge of a new head. Review and destructive-action gates remain authoritative.

# Digitaltwin: OpenCode and Commander product specification

**Status:** Proposed target architecture. This specification approves no migration, provider login, deployment, or runtime effect.

## Purpose

Digitaltwin is a self-hosted development cockpit for one software engineer.

OpenCode is the primary coding interface. It provides project organization, focused conversations, agent execution, and Git-oriented feedback. Digitaltwin adds one capability that an ordinary coding chat does not provide: a persistent Commander that remembers, coordinates, and keeps future commitments.

The user sees **Commander**. The selected Commander runtime is an implementation detail. Hermes is the initial candidate, not a product name or stable UI contract.

## User model

The user has:

- one global Commander conversation;
- multiple projects;
- multiple focused OpenCode sessions in each project;
- remote agent execution against the user's Git repositories.

A project is a context and navigation boundary. It starts an agent in the project's directory and keeps the conversation narrow. It is not an access-control boundary. An agent may work across services when the task requires it.

Commander is independent of projects. A persistent top-bar control opens the same Commander conversation from every OpenCode screen. Opening Commander preserves the current project session. Commander has visibly distinct branding and must never expose its underlying runtime name as its identity.

Mobile access is secondary. It uses the chosen OpenCode remote-web or pairing path. Digitaltwin does not create a separate mobile chat application.

## OpenCode owns project chats

Project chats use upstream OpenCode directly.

```text
Project chat → OpenCode → remote project workspace → Git
```

Kirei does not receive, proxy, store, approve, or deliver ordinary project-chat prompts, transcripts, tool calls, or agent events. A project chat remains usable if Kirei is unavailable.

OpenCode and Git are the developer feedback loop. OpenCode presents session progress and repository changes. Git remains the durable authority for commits, branches, diffs, and pull requests.

Digitaltwin must install its OpenCode additions globally through operator-managed configuration. Project configuration must not replace Commander behavior or gain access to its runtime credentials.

## Commander is the Digitaltwin feature

Commander is a durable, cross-project counterpart for the user. It can retain its own memory and skills, connect current work across projects, and perform scheduled check-ins.

Commander does not replace normal project coding chats. It is used for work such as:

- asking what is currently in progress;
- deciding which project work needs attention;
- retaining a follow-up for a future date;
- reviewing a scheduled check-in and deciding whether to delegate work;
- coordinating a task that crosses project context.

The Commander implementation may run through Herdr so Digitaltwin can retain one runtime adapter for non-OpenCode CLIs. Herdr is not required in the normal OpenCode project-chat path.

The Commander bridge is deliberately thin:

```text
OpenCode Commander control → Commander bridge → Commander runtime
                                      ↕
                             Kirei future-task API
```

The bridge must preserve a durable Commander conversation identity. It must support streaming, steering, cancellation, reload, and result collection. Whether an upstream OpenCode plugin can provide the required top-bar control and transparent external conversation remains a validation gate.

## Kirei owns future commitments

Kirei is not the general chat control plane. It is the durable time-and-work service for Commander.

Kirei accepts a one-time future-task request, stores a durable record, and uses its worker queue to execute due work. Its existing job primitive supports `available_at`, idempotency keys, leases, retry handling, and uncertain-effect recovery. A future-task domain is still required; a queue job alone cannot represent changes, cancellation, or an execution history.

Each future task records:

- a stable task id;
- the creating actor and originating Commander or project context;
- a target, which defaults to Commander;
- task text and relevant project or repository references;
- one-time timing with an explicit timezone;
- state: scheduled, running, completed, failed, canceled, or uncertain;
- execution attempts and outcomes.

When due, a future task appends a visible check-in message to the one Commander conversation. It states the stored task and asks the user what to do. It does not start project work automatically. The result appears in Commander only. It does not inject a message into the originating project chat.

An agent may create a future check-in from a project chat. That check-in still targets Commander unless the request explicitly names another target. A due task must not silently revive a stale project session.

The user's reply determines whether Commander assesses the item, starts project work, reschedules it, or cancels it. The task record must show that outcome.

## Agent scheduling capability

All supported agents receive one logical future-task capability. Kirei exposes a typed API and owns validation, persistence, scheduling, cancellation, and execution records.

The capability has two transport adapters:

- an MCP tool for Commander and other MCP-capable agents;
- an OpenCode global custom tool for project agents.

Both adapters call the same Kirei API. Neither adapter writes queue rows directly or implements its own scheduler.

The first capability set must support:

- create a one-time future task;
- list relevant future tasks;
- read one task and its outcome;
- update timing or task text before execution;
- cancel an unstarted task.

Recurrence may be added after one-time execution, restart recovery, and cancellation are proven. Recurrence must use an explicit timezone and define how a missed occurrence is handled.

Digitaltwin ships a shared `future-work` skill. It explains when a future check-in is useful, how to express a useful task, how to select a timezone, and how to update or cancel a commitment. A concise baseline instruction tells every supported agent that the capability exists and that it must wait for a returned task id before claiming work is scheduled. The skill holds the operating detail; the injected instruction makes the capability discoverable.

## Commander learning visibility

Commander may retain compact durable facts and reusable procedures through its selected runtime. A learning action must appear as a compact item in Commander when it is accepted or staged. The item identifies whether it changed memory or a skill and gives a concise summary. It must not expose the full private transcript by default.

The Commander bridge, not a terminal-only runtime notification, is responsible for presenting these items in the OpenCode Commander conversation. A full learning-history visualizer is deferred. Obsidian is not part of the first release.

The cadence and approval policy for background learning remain open. The first configuration must record whether memories write automatically, whether skill changes are staged for review, and the selected notification detail.

## Authority and limits

The user deliberately directs and steers agents. Project selection is primarily a context choice, not a Kirei approval gate.

Scheduled execution still has an explicit, observable boundary:

- a future-task record is a durable commitment, not a hidden prompt;
- the task result identifies the triggering record and the work it started;
- a runtime failure remains failed or uncertain until reconciled;
- a scheduled task cannot claim success without a recorded outcome;
- runtime tool permissions and external service authentication remain independent of agent instructions.

Exact Git-version approvals, review gates, and a broader workflow ledger are optional later Kirei capabilities. They are not prerequisites for the OpenCode-first product.

## Out of scope

This product direction excludes:

- Mattermost channels, threads, bots, mobile builds, and push delivery;
- Kirei mediation of ordinary project chats;
- a replacement OpenCode project/session UI;
- a Digitaltwin-specific mobile application;
- an Obsidian integration or a separate learning-history application;
- automatic migration of existing Mattermost conversations;
- an agent-created independent scheduler outside Kirei;
- automatic code changes, merges, or deployment caused solely by a schedule.

## Validation gates

The following are not yet proven in the selected versions:

1. An unmodified upstream OpenCode installation can host a stable global Commander control through a supported extension point.
2. The Commander bridge can show a transparent persistent conversation, stream replies, steer active work, cancel it, and recover after a restart.
3. A remote OpenCode session works through the selected authenticated desktop and mobile access path.
4. A direct OpenCode project session can create, modify, and recover real Git work in the intended remote workspace.
5. Kirei can wake the selected Commander runtime exactly once for a due future task and reconcile an interrupted delivery.
6. The shared skill and baseline instruction cause Commander and project agents to use the same scheduling capability correctly.

Gate 1 is the first implementation validation. Do not build the Commander bridge, future-task API, or learning integration before an unmodified pinned OpenCode installation proves a supported global Commander control and conversation surface. A failure means Digitaltwin must choose an upstream contribution or a deliberately maintained small UI patch; it must not depend on DOM injection.

After Gate 1 passes, the next validation slice uses one disposable remote repository. It proves direct OpenCode work, cancellation, restart behavior, and mobile access before any Mattermost removal or Kirei workflow redesign.

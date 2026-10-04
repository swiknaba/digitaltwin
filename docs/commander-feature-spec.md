# Commander: feature behavior

Approved high-level behavior, consolidating the [Phase 0 specification](agent-fleet-architecture-and-review.md), sections 11–20. This describes the intended feature, not current readiness or an implementation plan.

## One main conversation

Commander is our main interface to the agent team. Through normal conversation, we can ask questions, request work, change direction, and check progress.

Project channels and task threads hold detailed questions, progress, reviews, and results. Commander chat brings back important milestones, approval requests, blockers, and results with links, rather than copying every message.

Commander uses context across our projects while checking who can act in each channel. Separate fleets do not share private context.

## Understand the request before acting

Commander uses the thread, named project, earlier conversation, and actual running work to understand requests such as “also add a search box.”

If several tasks fit, Commander asks a short question before acting. It makes the chosen project and task clear and never silently switches the target.

New work gets its own workflow and project thread. Commander selects the appropriate existing thread from context rather than asking us to choose it each time. Follow-ups stay with their existing task. It asks only when the context is insufficient or genuinely ambiguous.

## Know who sent each instruction

Kirei records whether an instruction reaches a worker directly from a human or through Commander.
It separately retains the authenticated human request and source message behind the work.
Commander’s generated instructions do not become direct human instructions, even when they follow a human request.

Every worker prompt and follow-up includes backend-verified sender context.
Worker base instructions explain the human and Commander roles and how forwarded requests differ from generated follow-ups.
Prompt text alone cannot establish sender identity or human approval.
Backend-generated phase and review instructions remain separate from the attributed request text.

Project threads show who sent an instruction and link its originating request when accessible:

- **Human:** Alice writes “Add search” directly in the task thread.
- **Commander, forwarding Alice:** Alice asks in Commander chat; Commander forwards or rephrases that request for the worker.
- **Commander, follow-up:** Commander writes “Also check keyboard navigation” within already authorized work; this is not a new instruction from Alice.

Kirei records forwarding or rewriting, the target task and session, and the request relationship.
Queued delivery, retries, and recovery retain the original attribution.
Attribution explains an instruction’s source; it grants no additional permissions and cannot replace exact human approvals.

## Delegate and keep work separate

Commander delegates normal coding and research to workers. Coding follows specification and approval, plan and approval, implementation and review, then a pull request. Both specification and plan are reviewed before human approval. Approvals name the task and exact version. Opening a pull request does not automatically merge or deploy it.

Commander chooses a suitable model for each task using its [base instructions](../commander/AGENTS.md).
Simple work uses Haiku or Lunar; medium work uses Sonnet or Terra; complex work uses Opus, Fable, or Sol.
Model names map to available backend-verified profiles. Explicit human choices take precedence.
Writer and Reviewer selections retain different providers and model families.

Parallel tasks in one repository use separate branches and worktrees. Each task’s Writer and Reviewer share its worktree and take turns.

Follow-ups reuse the relevant conversation; unrelated tasks start fresh. Only Commander starts independent fleet sessions. Workers ask for approval for additional independent sessions. Already authorized workflow roles need no repeated spawn approval. Workers may use their harness’s subordinate agents within their session.

Commander chat has no coding review cycle. Commander may make a targeted emergency change through available tools; ordinary feature work still goes to workers. Destructive or irreversible operations require a specific second confirmation.

## Questions, progress, and controls

Workers ask questions in the task thread; we can answer there or through Commander. Results explain what changed, what was checked, remaining problems, and artifact or pull-request links. Replies return to their source conversation. “Received,” “queued,” and “delivered” mean different things.

We can ask for status, add instructions, pause, resume, cancel unfinished work, or finish delivered work. Commander clarifies the target. Pause lets the current step finish but prevents the next. Resume preserves results and rechecks the normal gates. Cancel confirms what actually stopped without erasing results. Finish explicitly closes delivered work; silence does not.

During review, new Writer instructions wait. They cannot change the reviewed version or start a competing Writer. Commander explains the wait and releases instructions when work may continue.

## Hermes memory, skills, failures, and restarts

Commander runs through the latest supported Hermes Agent stable release. Hermes publishes dated stable tags, not minor-line tags. A normal Runtime rebuild can advance to the next stable release. Hermes owns Commander-native Markdown memory, SQLite conversation history and search, and reusable skills. Its persistent profile and workspace stay on the Runtime volume. Hermes reads Commander instructions and memory on a new conversation.

Hermes, not Grok, is the Commander harness. Hermes natively supports optional xAI Grok inference
through `xai`/`grok` with an existing `XAI_API_KEY`, or `xai-oauth`/`grok-oauth` after an operator
performs its OAuth login. The user has not selected a Commander default model, so this release sets
none: an operator selects the provider and model in the private Hermes profile. Gemini remains
optional and is never assumed. No key, OAuth token, browser login, paid call, or live-provider
claim is created by this implementation.

Kirei does not store Commander knowledge, mirror memory into Markdown, or adapt an external memory provider. Mattermost retains chat transcripts in PostgreSQL for chat delivery and audit. Hermes history serves Commander recall. These stores have different purposes.

Kirei remains authoritative for verified sender provenance, authorization, project membership, workflow state, sessions, jobs, approvals, routing, delivery receipts, and recovery. Hermes-provided memory or skill content cannot grant permission, identify a sender, approve a change, or start an independent fleet session.

Commander initialization creates a local Git repository in the Commander workspace. It tracks the Commander-only `SOUL.md` and instructions, Markdown memory, curated skills, and separately stored learned skills. Hermes gets its own `HERMES_HOME` there. Its generic Runtime defaults are the official packaged `weekly-review-planning` and `grounded-citations` skills; agent-authored skills go to `learned-skills`.

The shared worker baseline is the Wagglebot [reference setup](https://github.com/swiknaba/wagglebot/tree/main/examples/reference-setup). Once the first Wagglebot release with company-subdirectory support is published, connect it with `wagglebot connect https://github.com/swiknaba/wagglebot.git examples/reference-setup`, then provision compatible worker harnesses through the documented Wagglebot flow. Commander can use the shared library, but its Runtime-local `AGENTS.md` and `SOUL.md` define its coordinator role. Hermes is not a Wagglebot provisioning target; its native memory, SQLite history, and learned skills remain per Commander profile. Kirei continues to validate role selection and every workflow authorization. This is role guidance and profile isolation, not a security boundary between processes that share the Runtime user.

The workspace ignores SQLite databases, WAL files, credentials, and runtime state. The first release creates no automatic Kirei commit job, remote, or push schedule. Therefore, local Git history is not a backup. Automated commits and remote backup need a separate retention, credential, conflict, and recovery design.

Explicit steering changes Commander instructions. Hermes learns through its native memory and skills mechanisms. No Kirei memory grooming is required.

After restart, Commander restores verified task state and reuses healthy matching conversations. Missing conversations or actions with uncertain outcomes are reported for reconciliation. It never invents success, repeats a potentially completed action, or creates replacement work to clear an error.

## What works today

Real service connections, replies, duplicate handling, and restart recovery pass automated tests with a scripted agent. Live provider behavior remains unverified, and production dispatch is disabled in code. Commander enrollment, Git/deployment/emergency tools, and durable memory have implementation or acceptance gaps.

## Agreed first version

The first enabled version focuses on conversation, status, and routing for existing projects. Project enrollment and emergency tools come afterward.

Commander selects the correct thread from context itself, with clarification only when needed. Hermes retains Commander memory, conversation history, and skills; Kirei retains the durable orchestration record.

# Authenticated harness setup

Status: requirements draft. The current application still requires `roles.json`.

## Setup

Authenticate the supported harnesses you want to use inside Runtime.
The application detects their authentication status and uses their configured model defaults.
Normal setup requires no Writer/Reviewer role file, model labels, provider labels, or launch arguments.
Do not maintain a model catalog or pinned model IDs for default role selection.
Resolve each harness's configured default when starting a new session.
Existing sessions retain their selected configuration when resumed.
Accept a specific model only as an explicit human override for that task.
Record the actual model for audit when the harness reports it; otherwise record it as unknown.
Do not ask the operator to supply model metadata for audit.

Example: authenticate Codex and Claude. The application can use Codex as Writer and Claude as Reviewer.
Authenticate Gemini later, and it becomes another available choice.

## Task selection

- Select different available harnesses for Writer and Reviewer when at least two are available.
- Honor explicit human harness and model instructions for that task.
- Report an unavailable requested harness or model instead of silently substituting it.
- Explain the missing second harness when an independent review pair cannot be selected.
- Record the selected pair with the workflow. Preserve it across restarts and follow-ups.

Example: “Use Claude to write this and Codex to review it” overrides automatic selection.

Selection among more than two harnesses still needs an application policy.
Explicit instructions that request the same harness for both roles also need a defined review policy.

## Detection

Runtime owns harness authentication checks. The backend receives availability, not credentials.
Use supported authentication-status commands where available.
Installed executables and existing credential files alone do not prove authentication.
Distinguish authenticated, unauthenticated, and unknown results.
Do not run a model prompt merely to discover authentication.

If a harness cannot report authentication reliably, allow a minimal operator declaration for that harness.
The declaration describes availability; it does not guarantee that the provider will accept a future request.

## Changes required

- Add Runtime authentication detection and a typed inventory boundary.
- Select roles from that inventory when a workflow starts.
- Add structured handling for explicit human selections.
- Replace the operator role-file requirement and its activation-file hash dependency.
- Reconcile the current provider-and-model-family review restriction with the requested different-harness rule.
- Replace the local setup instructions after implementation and verification.

Keep this draft separate from the runnable runbook until these changes exist.

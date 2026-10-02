# Workflows
Owns `workflows`, `workflow_requests`, `approvals` and `queued_messages`: the durable project workflow from start request to archive.
Public API: `Catalog` (reads), `Transitions` (locked, versioned phase writes), `Requests`, `Approvals`, `QueuedMessages`, `PhasePrompts`, `Policy`, `Records` (strict role JSON parsing), `Dto::*` and `Errors::*`.
Effects (chat posts, Herdr prompts, git evidence, sessions) live in `Services::Workflows`.

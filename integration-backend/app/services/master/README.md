# Master use cases
Effects around the commander domain: Master prompts, request tokens, follow-up routing and delivery, approvals and chat notices.
Use cases: `IngestPrompt`, `Recover`, `Reply`, `RouteFollowup`, `ReconcileFollowup`, `RecordApproval`, `Tools`, `AuthorizeRequest`; job handlers: `HandleMasterPrompt` (master.prompt), `Dispatch` (master.dispatch), `DeliverFollowup` (session.followup), `HandleWorkflowPrompt` (workflow.prompt).
`Tools` returns typed `Dto::ToolResponse` values; `Adapters::Http::Master` serializes them to the tool JSON.

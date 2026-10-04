# Commander use cases (internal `Commander` namespace)
Effects around the Commander domain: Commander prompts, request tokens, follow-up routing and delivery, approvals and chat notices. The Ruby namespace and job/route names remain `Commander` for wire and persistence compatibility.
Use cases: `IngestPrompt`, `Recover`, `Reply`, `RouteFollowup`, `ReconcileFollowup`, `RecordApproval`, `Tools`, `AuthorizeRequest`; job handlers: `HandleCommanderPrompt` (commander.prompt), `Dispatch` (commander.dispatch), `DeliverFollowup` (session.followup), `HandleWorkflowPrompt` (workflow.prompt).
`Tools` returns typed `Dto::ToolResponse` values; `Adapters::Http::Commander` serializes them to the tool JSON.

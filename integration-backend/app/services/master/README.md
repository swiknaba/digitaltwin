# Commander use cases (internal `Master` namespace)
Effects around the Commander domain: Commander prompts, request tokens, follow-up routing and delivery, approvals and chat notices. The Ruby namespace and job/route names remain `Master` for wire and persistence compatibility.
Use cases: `IngestPrompt`, `Recover`, `Reply`, `RouteFollowup`, `ReconcileFollowup`, `RecordApproval`, `Tools`, `AuthorizeRequest`; job handlers: `HandleMasterPrompt` (master.prompt), `Dispatch` (master.dispatch), `DeliverFollowup` (session.followup), `HandleWorkflowPrompt` (workflow.prompt).
`Tools` returns typed `Dto::ToolResponse` values; `Adapters::Http::Master` serializes them to the tool JSON.

# Sessions use cases
Effects around the sessions domain: Herdr starts and stops, credential files (`<id>.token`, `<id>.request-token`) and chat notices.
Use cases: `ReserveSession`, `BootstrapController`, `StopWorkflowSessions`, `ReconcileOperation`, `PostWorkerChat`; job handlers: `ExecuteOperation` (session.start/stop), `Renew` (session.renew).
Helper: `CompleteOperation` settles a proven operation. `ReconcileOperation` reads raw `master_requests` until Task 9.

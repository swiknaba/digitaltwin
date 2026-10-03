# Commander
The Commander drives the fleet (after Commander Shepard in Mass Effect). It owns `master_requests`, `followups`, `conversation_bindings` and `confirmations`.
Public API: `MasterRequests`, `Followups`, `Bindings`, `Confirmations`, `Dto::*` and `Errors::*`. Malformed rows fail closed with `Errors::MalformedRecord`.
Callers hold the "Commander" `Platform::Lock` for Commander requests and the workflow's lock for follow-ups.
Herdr prompts, credential files, jobs and chat notices live in `Services::Master`. `Services` is the composition root until Task 10.

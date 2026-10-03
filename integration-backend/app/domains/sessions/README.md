# Sessions
Owns `sessions`, `session_operations` and `callbacks`: agent sessions, their start and stop operations, and Worker callback receipts.
Public API: `Registry` (reads), `Operations` (reserve, stops, proven state), `Authenticate`, `Callbacks`, `Renewals`, `ConfigurationPolicy`, `Records`, `Dto::*` and `Errors::*`.
A scope is one workflow role, or the Commander (`workflow_id` nil). Callers hold the scope's `Platform::Lock`.
Herdr, credential files and outbox notices live in `Services::Sessions`.

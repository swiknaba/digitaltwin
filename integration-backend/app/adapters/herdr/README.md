# Herdr adapter
Speaks the local Herdr JSON-lines socket protocol and translates replies into DTOs.
Public API: `Client` (`pane`, `prompt`, `start`, `create_workspace`, `panes`, `close`), `Dto::*`, `Errors::ProtocolViolation`.
Schema evidence: `agent-runtime/contracts/herdr-v0.9.3.schema.json`.

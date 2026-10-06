# Commands
Owns the chat command grammar addressed to the agent and Worker bots.
Public API: `Parser#call(body:, commander_handle:, agent_handle:)` returns a `Dto::Command` or nil.

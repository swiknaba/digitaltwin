# MCP adapter
Standalone stdio MCP bridge for the Commander agent; it forwards tool calls to `/internal/master/*`.
Public API: `Server#serve`, `Server::ToolGateway`, `HttpTools`.
These two files need only the standard library and sorbet-runtime; `bin/mcp` loads them by path.

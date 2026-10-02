# Commander

The Commander drives the fleet (after Commander Shepard in Mass Effect). This domain is the backend's orchestration boundary. It turns verified inbox events and
signed internal callbacks into routing, approval, workflow, review, and session actions.
It also exposes the narrow MCP tool bridge; authorization and input validation happen
here before work is handed to other domains.

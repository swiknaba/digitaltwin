# Workflows

This domain models and advances the durable project workflow. It provisions a workflow,
coordinates phase changes, serializes updates with database-backed locks, and applies the
policy for approvals, reviewer diversity, and dispatch. The policy currently keeps live
dispatch closed by default; external effects remain delegated to jobs and sessions.

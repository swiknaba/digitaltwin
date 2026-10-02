# Jobs

This domain provides the durable work queue used by the rest of the backend. `Store`
persists idempotent jobs and their leases, retries, blocks, and effects; `Worker` claims
them and dispatches registered handlers. Domain code should enqueue work here rather
than perform a recoverable external effect inline.

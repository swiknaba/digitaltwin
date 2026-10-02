# Reviews

This domain accepts signed review callbacks and coordinates artifact and review evidence
against a workflow's required gates. It reads Git evidence through `Adapters::Git::Evidence`, records the
result, and queues the next allowed release step. It does not treat an unverified callback
or an arbitrary filesystem path as review evidence.

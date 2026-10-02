# Reviews use cases
Effects around the reviews domain: Herdr reviewer prompts, git artifact and review evidence, workflow phase changes, queued-message release and chat notices.
Use cases: `ArtifactReady`, `ReviewFinished`, `QueueCallback`, `QueueRelease`; job handlers: `DispatchReview` (review.prompt), `ReleaseQueued` (review.release), `ApplyCallback` (review.callback).
Helpers: `CallbackSession` resolves a callback's session from a `Dto::BearerToken` or `Dto::QueuedSession`; `VerifySettled` checks the live Herdr conversation.
`ReleaseQueued` reads raw `followups` until Task 9.

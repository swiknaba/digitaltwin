# Projects use cases
Combine `Domains::Projects` path rules with `Adapters::Git`.
Public API: `Enroll#call`, `ResolveRepository#call(slug:)`, `PrepareWorktree#call(slug:, workflow_id:, branch:)`.
Expected rejections are failure results with `Domains::Projects::Dto::ErrorCode`.

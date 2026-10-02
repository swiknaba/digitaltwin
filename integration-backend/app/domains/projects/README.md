# Projects
Owns `projects`: the mapping of a chat channel to one GitHub repository checkout.
Public API: `Directory`, `Register#call`, `WorkspacePaths` (pure path rules), `RepositoryIdentity`, and `Dto::*`.
Git-running use cases live in `Services::Projects`: `Enroll`, `ResolveRepository`, `PrepareWorktree`.

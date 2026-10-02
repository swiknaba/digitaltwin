# Projects

This domain enrolls projects and manages their local Git workspaces. It validates a
repository's canonical identity, creates contained worktrees for workflows, and invokes
`Adapters::Git` for git queries and private repository creation. It does not decide the
workflow policy or send chat messages.

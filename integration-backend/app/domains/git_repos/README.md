# Git repos

This domain wraps the source-control hosting service (a "forge", such as GitHub). It
creates private repositories and clones an enrolled repository into a requested local
destination. It is deliberately small: project identity and workspace safety live in
`projects`, while this client owns only the hosting-service command boundary.

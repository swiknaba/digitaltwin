# Forge

“Forge” means the source-control hosting service, not a workflow phase. This domain
creates private repositories and clones an enrolled repository into a requested local
destination. It is deliberately small: project identity and workspace safety live in
`projects`, while this client owns only the hosting-service command boundary.

# Adapters
Translate vendor, transport, and filesystem data into DTOs at the boundary.
`Adapters::<X>` may reference `Platform` and `Domains::*::Dto`.
`Adapters::Http` and `Adapters::Mcp` may also reference `Services` and any `Dto`.

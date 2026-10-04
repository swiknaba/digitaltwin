# HTTP adapter
Kirei commanders for `/internal/callbacks/*` and `/internal/commander/*`.
They parse request bodies into `Dto::*`, delegate, and keep the wire bodies and status codes stable.

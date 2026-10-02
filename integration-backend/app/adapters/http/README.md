# HTTP adapter
Kirei controllers for `/internal/callbacks/*` and `/internal/master/*`.
They parse request bodies into `Dto::*`, delegate, and keep the wire bodies and status codes stable.

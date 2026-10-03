# Services
Stateless use cases with a `.call` entry point; they compose domains, adapters, and platform.
May reference anything except `Domains::*::Entities` and `Platform::*::Entities`.
Failures that callers expect return `Kirei::Services::Result` built through `Platform::Failure`.

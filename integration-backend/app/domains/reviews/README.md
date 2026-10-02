# Reviews
Owns `reviews`: the numbered review rounds of a workflow gate (at most three), their reviewer prompt dispatch state and their verdicts.
Public API: `Rounds` (open, reads, dispatch state), `Verdicts` (record a round's verdict once), `Dto::*` and `Errors::*`.
Callers hold the workflow's `Platform::Lock`. Malformed rows fail closed with `Errors::MalformedRecord`.
Herdr prompts, git evidence, jobs and chat notices live in `Services::Reviews`.

# Repository Work

Read `docs/repository-layout-and-parallel-build.md` and `docs/interfaces/service-boundaries.md` before component implementation.
The Phase 0 specification and plan define behavior; the layout document defines source paths.

## Ownership

- Component workers own their assigned top-level folder and its dependency lockfiles.
- The integrator owns root files, `scripts/`, `tests/`, and shared `docs/interfaces/` contracts.
- The integration backend owner coordinates migration numbers, shared domain entities, and callback/MCP client source.
- Propose cross-owner edits through the integrator. Do not overwrite another worker's changes.
- Use separate branches and worktrees. Merge in dependency order.

## Validation

- Record exact upstream revisions and sanitized contract evidence before implementing dependent adapters.
- Keep unresolved Task 1 checks explicit. Documentation inspection is not a live compatibility test.
- Tasks 6–10 remain blocked by missing required Herdr, authenticated chat, idle, and selected Master MCP evidence.
- Preserve separate Kirei/Mattermost database ownership and production infrastructure ownership.
- Store no signing keys, provider login state, or credentials in Git or images.
- Keep LiveKit/voice in Phase 1 and LiteLLM/MCP direction after Phase 2.
- Record checks, evidence gaps, and changed interfaces in each worker handoff.

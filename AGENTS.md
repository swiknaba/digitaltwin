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
- Tasks 6-10 remain blocked by missing required Herdr, authenticated chat, idle, and selected Master MCP evidence.
- Preserve separate Kirei/Mattermost database ownership and production infrastructure ownership.
- Store no signing keys, provider login state, or credentials in Git or images.
- Keep LiveKit/voice in Phase 1 and LiteLLM/MCP direction after Phase 2.
- Record checks, evidence gaps, and changed interfaces in each worker handoff.

## Code Quality and Type Safety

- All production code must be type-safe when its language supports static type checking. Keep public and private interfaces explicit; do not use loose, broad, or unchecked data shapes where a precise type can be modelled.
- Ruby code must use Sorbet. New and changed Ruby source files require `# typed: strict` and `# frozen_string_literal: true`, `extend T::Sig` where methods are defined, signatures for public and private methods, and explicit `T::Struct`/domain value types at application boundaries. Follow Kirei's thin-controller, typed-service, immutable-domain-object approach.
- Use typed result values for expected business outcomes. Reserve exceptions and rescue for genuine exceptional boundary failures, and convert those failures into an explicit typed result at the boundary.
- Do not use `T.untyped`, `T.unsafe`, unstructured or overly broad hash payloads, unverified casts, `typed: false`/`typed: ignore`, or blanket suppressions to make checks pass. Define a precise `T::Struct`, typed hash, RBI, shim, or wrapper for dynamic framework and dependency boundaries, then verify it.
- Services are stateless and expose a small, explicit API (normally `.call`); controllers only validate/translate requests and delegate domain work. Keep persistence, transport, filesystem, and subprocess adapters at explicit typed boundaries rather than leaking their raw values through domain code.
- Define exactly one concrete class per Ruby file. A file may be wrapped by namespace modules or an existing enclosing class, but it must not define helper, value, error, transport, or nested classes alongside its primary class. Put each such class in its own appropriately named file and let Zeitwerk load it.
- Use Kirei's framework abstractions for persistence, typed row resolution, transactions, and JSONB serialization. Prefer a typed `Kirei::Model` and its query API over injected `Sequel::Database` handles, hand-written row mappers, JSON serialization helpers, or SQL literals. Introduce low-level Sequel or database-specific functionality only for a demonstrated Kirei framework gap; keep it narrow and document why the framework API cannot express it.
- Prefer descriptive names and named parameters when multiple arguments could be confused. Do not assign inside a conditional; avoid ambiguous booleans and string state machines when an enum/value type expresses the state; make `case` branches exhaustive where possible; and avoid relying on incidental ordering or dynamic behavior.
- Every Ruby file uses double-quoted strings; use the project RuboCop configuration to enforce that convention. Write comments only for non-obvious intent (and include an owner and date in TODOs). Avoid rescue modifiers and broad rescues that erase cause/context; handle a narrow real boundary failure and preserve a safe typed failure result.
- Run the whole-project type checker as part of validation (for Ruby, `bundle exec spoom srb tc` or the project equivalent) plus the relevant tests and RuboCop. Focused contract checks are supplemental only and never substitute for a passing whole-project type check. Classify and fix dependency/RBI failures as well as application failures; do not weaken or suppress checks merely to obtain a clean result.

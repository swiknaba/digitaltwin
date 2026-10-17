# Integration Backend

## Ruby conventions

- Add `# typed: strict` and `# frozen_string_literal: true` to every Ruby source file.
- Extend `T::Sig` and add signatures for public and private methods.
- Model boundaries with explicit types and typed results. Do not use `T.untyped`, `T.unsafe`, unchecked casts, broad hashes, or blanket suppressions.
- Define one concrete class or module per Ruby file. Its full constant path must match the `app/` path after Zeitwerk inflection. Namespace wrappers may enclose it. `bin/check-zeitwerk` boots the backend and runs `Zeitwerk::Loader.eager_load_all`, so Zeitwerk validates the loader's expected constants.
- Use Kirei persistence abstractions and typed row resolution. Add low-level Sequel only for a demonstrated Kirei gap.
- Define class methods with `def self.`, not `class << self`. Make private methods private inline: `private def name` and `private_class_method def self.name`. Do not use a bare `private` section. RuboCop enforces both rules.
- Use double-quoted strings. Handle only narrow, real boundary failures and preserve their cause in typed results.

## Layout

- `app/` has four Zeitwerk layers.
  - `domains/future_tasks/` owns durable future commitments, their executions, and their disposition records.
  - `services/` holds the due-job handler and the small composition root.
  - `adapters/opencode/` is the sole delivery boundary. It fails closed until an operator wires an existing authenticated OpenCode session.
  - `platform/` holds shared primitives: jobs, lock, transaction, failures, JSON boundary types, and the process heartbeat.
- Domains reference only their own code, `Platform`, and other contexts' `Dto`. Domains never reference `Services` or `Adapters`.
- Nothing outside a context references its `entities/`.
- Persistence uses Kirei models where it adds value; the future-task transition service may use a narrow transaction-scoped Sequel dataset for atomic state changes.

## Loading dependencies

- Gemfile groups are the sole production, development, and test loading boundary. No dependency may use `require: false`.
- `app.rb` alone invokes `Bundler.require` for active groups. Code under `app/` must not call `require`; Zeitwerk loads application classes.
- An exception needs an explicit, documented bootstrap boundary and tests.

## Operational invariants

- Test migrations through real Rake tasks against an empty disposable database. Do not preload the application or spec helper.
- Delivery uses one key per execution generation. If the bridge outcome is uncertain, persist `uncertain` and stop; do not blind-retry an externally visible Commander action.
- Edits, cancellation, and dispositions require an expected task version and preserve the prior execution record.

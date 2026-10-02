# Integration Backend

## Ruby conventions

- Add `# typed: strict` and `# frozen_string_literal: true` to every Ruby source file.
- Extend `T::Sig` and add signatures for public and private methods.
- Model boundaries with explicit types and typed results. Do not use `T.untyped`, `T.unsafe`, unchecked casts, broad hashes, or blanket suppressions.
- Define one concrete class per Ruby file. Keep controllers thin and services stateless with a small `.call` API.
- Use Kirei persistence abstractions and typed row resolution. Add low-level Sequel only for a demonstrated Kirei gap.
- Use double-quoted strings. Handle only narrow, real boundary failures and preserve their cause in typed results.

## Layout

- `app/` has four Zeitwerk layers. See `docs/superpowers/plans/2026-10-02-backend-ddd-refactor.md` for the full rules.
  - `domains/<ctx>/` holds bounded contexts that own tables and invariants. Each context has private `entities/`, public `dto/` and `errors/`, and public services.
  - `services/` holds cross-domain use cases and job handlers.
  - `adapters/` holds vendor and transport translation: Mattermost, Herdr, git, HTTP, and MCP.
  - `platform/` holds shared primitives: jobs, lock, and audit.
- Domains reference only their own code, `Platform`, and other contexts' `Dto`. Domains never reference `Services` or `Adapters`.
- Nothing outside a context references its `entities/`.
- Public services return `Kirei::Services::Result`. Persistence uses `Kirei::Model` only. Do not access raw tables with `db[:table]`.
- `spec/contracts/architecture_boundaries_spec.rb` enforces these rules.

## Loading dependencies

- Gemfile groups are the sole production, development, and test loading boundary. No dependency may use `require: false`.
- `app.rb` alone invokes `Bundler.require` for active groups. Code under `app/` must not call `require`; Zeitwerk loads application classes.
- An exception needs an explicit, documented bootstrap boundary and tests.

## Operational invariants

- Test migrations through real Rake tasks against an empty disposable database. Do not preload the application or spec helper.
- Advance Mattermost history checkpoints only through accepted snapshot coverage. Retain and recover when the result reaches a cap or fetching fails.
- Quarantine permanent rejections idempotently. Retry transient failures without moving the checkpoint.

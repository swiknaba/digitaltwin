# OpenCode Commander Gate 1 evidence

**Status:** Not passed — documented UI extension point is absent from the inspected
release surface. Do not build the Commander bridge, future-task API, or learning
integration from this result.

## Inspected release

| Evidence | Result |
| --- | --- |
| Installed desktop CLI | `/Applications/OpenCode.app/Contents/Resources/opencode-cli` reports `opencode v2.0.27`. |
| Global plugin state | `opencode plugin list` reports `No plugins found`. No global or project plugin was installed or modified for this check. |
| Plugin contract | The release CLI supports plugin list/add/check/update/remove. Its server OpenAPI exposes plugin listing/update and plugin RPC, while the published plugin documentation describes hooks and custom tools. |
| Session control plane | The same release's OpenAPI exposes `session.create`, `session.prompt`, durable session log streaming, inbox update/cancel (steering), and `session.interrupt`. It also exposes browser/app pairing. |
| UI extension surface | The inspected CLI/OpenAPI has no top-bar, toolbar, sidebar, view, or UI-registration operation. The released public plugin documentation describes server-side hooks/tools, not a desktop/web UI contribution API. |

The session controls demonstrate that a future bridge could own a durable OpenCode
session and implement prompt, stream, steer, and cancel without DOM automation. They
do **not** prove a supported global Commander control or a transparent branded
conversation UI, and must not be misrepresented as satisfying Gate 1.

## Required Gate 1 pass criteria

On a pinned upstream OpenCode version, record one supported API that lets an
operator-global extension:

1. add an always-visible global Commander control without a DOM selector or patch;
2. open the one durable Commander conversation while preserving an active project
   session;
3. display and reconnect streamed external/session output under the Commander brand;
4. obtain a trusted user/conversation proof for the bridge without exposing a static
   credential to project configuration.

The proof must use a disposable project and an installed, version-pinned extension.
It must show duplicate/reconnect, steer, cancel, and stale-capability rejection. It
must not require a paid model or a provider login; a free configured model may be
used only if a model turn is genuinely needed.

## Decision

The smallest source-spec-consistent next step is an **upstream contribution or a
deliberately maintained small OpenCode UI patch** that supplies the four pass
criteria above. A global custom tool, a slash command, a plugin RPC, or an external
browser window alone is not an equivalent substitute because it does not provide the
required persistent top-bar control and transparent Commander surface.

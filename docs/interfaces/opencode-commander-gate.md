# OpenCode Commander Gate 1 evidence

**Status:** Failed for the pinned OpenCode `v2.0.27` plugin contract. A real
operator-global local plugin loaded successfully, but OpenCode advertises it as a
server-only feature. No supported UI registration, Commander conversation view, or
trusted bridge-capability surface was available. Do not build the Commander bridge,
future-task API, or learning integration from this result.

## Inspected release

| Evidence | Result |
| --- | --- |
| Installed desktop CLI | `/Applications/OpenCode.app/Contents/Resources/opencode-cli` reports `opencode v2.0.27`; SHA-256 is `c60d9b61fe4ed3f1387efb6e101d81f052085ce64aada93d8e6937fbe80fbfa4`. |
| Global plugin state | `opencode plugin list` reports `No plugins found`. No global or project plugin was installed or modified for this check. |
| Plugin contract | The release CLI supports plugin list/add/check/update/remove. Its server OpenAPI exposes plugin listing/update and plugin RPC, while the published plugin documentation describes hooks and custom tools. |
| Session control plane | The same release's OpenAPI exposes `session.create`, `session.prompt`, durable session log streaming, inbox update/cancel (steering), and `session.interrupt`. It also exposes browser/app pairing. |
| UI extension surface | The inspected CLI/OpenAPI has no top-bar, toolbar, sidebar, view, or UI-registration operation. The released public plugin documentation describes server-side hooks/tools, not a desktop/web UI contribution API. |
| Live desktop observation | The running desktop application presents its ordinary session UI (project selector, session tab, prompt, model selector, and notifications) with no installed plugin and no visible Commander control. This is an observation, not proof that a supported global UI API is absent. |
| Live global-plugin probe | A symlinked local TypeScript plugin at `~/.config/opencode/plugins/digitaltwin-commander-gate-probe.ts` loaded successfully after a service restart. `GET /api/plugin` reports `id: digitaltwin-commander-gate-probe`, `source.type: local`, `state.status: active`, and only `features.server: true`. It exposes no UI/client/session/capability feature. |
| Installed contract mismatch | The first probe used the current public-doc named-function shape and was rejected. v2.0.27 requires a default definition with `id` plus `effect` or `setup`. The active probe uses the required default `setup` shape. Current web documentation therefore cannot substitute for release-bound evidence. |

The session controls demonstrate that a future bridge could own a durable OpenCode
session and implement prompt, stream, steer, and cancel without DOM automation. They
do **not** prove a supported global Commander control or a transparent branded
conversation UI, and must not be misrepresented as satisfying Gate 1.

## Reproduction and live result

The initial read-only inspection used the installed executable rather than a
downloaded or modified build:

```text
/Applications/OpenCode.app/Contents/Resources/opencode-cli --version
/Applications/OpenCode.app/Contents/Resources/opencode-cli plugin list
/Applications/OpenCode.app/Contents/Resources/opencode-cli api GET /openapi.json
```

The same release's `plugin --help` states that `plugin add` installs a package into
the active **global configuration**, and the CLI exposes no isolated configuration
flag. A live global-plugin experiment would therefore alter the active desktop
configuration before its clean removal. No such change was made during this
investigation. This is why a server-only plugin smoke test is not enough to close the
gate: it would prove loading only, not the required supported UI/capability contract.

It also consulted the published [plugin documentation](https://opencode.ai/docs/plugins/)
and [command documentation](https://opencode.ai/docs/commands/) on 2026-10-12. The
probe source is repository-local at
`commander/opencode-gate-plugin/commander-gate-probe.ts`; its one global symlink is
intentionally retained for manual testing. No DOM selector, API key, paid model, or
provider login was used. The Mac locked before a post-load desktop accessibility
snapshot could be captured, and no remote-web UI was opened. Those observations are
not needed to establish failure: the active plugin's release-bound feature contract
is server-only and cannot supply any of the required UI/capability criteria.

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

### Alternative only if the product specification changes

The smallest reduced-scope product would replace the top-bar/transparent-conversation
requirement with an operator-global `/commander` command that opens a separate,
explicitly branded Commander web route. OpenCode 2.0.27's global command and plugin
configuration can make this discoverable, while the OpenAPI session controls can
support the bridge behind it. This is a materially weaker UX: it does not preserve
the current project screen in one native OpenCode surface and does not meet the
current specification. Choose it only by an explicit product decision; it is not a
silent fallback.

#!/bin/sh

set -eu

readonly expected_revision="1f4d07a4a519185955ae8ab2ea3607805509e386"
readonly patch_names="0001-commander-gui-extension.patch 0002-commander-panel-safety.patch 0003-commander-bridge-ipc-seam.patch 0004-commander-bridge-workspace.patch 0005-commander-panel-actions.patch 0006-commander-desktop-bootstrap-harness.patch 0007-commander-playwright-ui-fixture.patch 0008-commander-runtime-validation.patch 0009-commander-discoverable-entry.patch 0010-commander-global-titlebar.patch 0011-commander-global-command.patch 0012-commander-global-dialog.patch 0013-commander-dialog-command-void.patch 0014-commander-component-fixture-types.patch 0015-commander-isolated-sidecar-port.patch 0016-commander-global-overlay.patch 0017-commander-native-request-docks.patch 0018-commander-project-session-tools.patch 0019-commander-closed-overlay-status.patch 0020-commander-internal-navigation.patch 0021-commander-native-composer.patch 0022-commander-overlay-container-sizing.patch 0023-commander-overlay-viewport-bounds.patch 0024-commander-overlay-titlebar-clearance.patch 0025-commander-model-persistence.patch 0026-commander-remove-legacy-bridge.patch 0027-commander-vite-fixture-browser-test.patch 0028-commander-hermes-overlay-transport.patch 0029-commander-hermes-events.patch 0030-commander-hermes-history.patch 0031-commander-hermes-model-picker.patch 0032-commander-hermes-admission-and-fallback.patch 0033-commander-overlay-follow-latest.patch 0034-commander-unified-hermes-model.patch 0035-commander-hermes-inventory.patch 0036-commander-worker-model-policy.patch 0037-commander-economical-worker-selection.patch 0038-commander-transcript-and-worker-picker.patch 0039-commander-worker-auto-and-history-hydration.patch 0040-commander-model-restore.patch 0041-commander-native-hydration.patch 0042-commander-user-attribution.patch 0043-commander-packaged-data-root.patch 0044-commander-packaged-sidecar-isolation.patch 0045-commander-packaged-service-registration.patch"

fail() {
  printf '%s\n' "prepare-opencode: $*" >&2
  exit 1
}

test "$#" -le 1 || fail "usage: $0 [/absolute/path/to/fresh-opencode-checkout]"

patch_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
source_root=$(CDPATH= cd -- "$patch_dir/.." && pwd)
repo_root=$(CDPATH= cd -- "$source_root/.." && pwd)
upstream=$(CDPATH= cd -- "${1:-$repo_root/local/opencode}" && pwd)
operator_example="$patch_dir/operator.env.example"
operator_launcher="$patch_dir/run-opencode-commander.sh"

test "$(git -C "$upstream" rev-parse --is-inside-work-tree 2>/dev/null || true)" = "true" || fail "target is not an OpenCode Git checkout"
test "$(git -C "$upstream" rev-parse HEAD)" = "$expected_revision" || fail "target must be OpenCode $expected_revision"
git -C "$upstream" diff --quiet || fail "target has unstaged changes"
git -C "$upstream" diff --cached --quiet || fail "target has staged changes"
test -f "$operator_example" || fail "missing operator environment example"
test -f "$operator_launcher" || fail "missing operator launcher"

cp "$operator_example" "$upstream/commander.env.example"
cp "$operator_launcher" "$upstream/run-opencode-commander.sh"
chmod +x "$upstream/run-opencode-commander.sh"

for patch in $patch_names 0046-commander-packaged-readiness-and-native-tone.patch 0047-commander-native-enabled-models.patch 0048-commander-packaged-cli-and-history.patch 0049-commander-cli-stage-identity.patch; do
  test -f "$patch_dir/$patch" || fail "missing patch $patch"
  git -C "$upstream" apply --allow-empty --check "$patch_dir/$patch"
  git -C "$upstream" apply --allow-empty "$patch_dir/$patch"
done

git -C "$upstream" diff --check
printf '%s\n' "Prepared OpenCode $expected_revision with Commander UI patches, commander.env.example, and run-opencode-commander.sh."

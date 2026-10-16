#!/bin/sh

set -eu

readonly expected_revision="1f4d07a4a519185955ae8ab2ea3607805509e386"
readonly patch_names="0001-commander-gui-extension.patch 0002-commander-panel-safety.patch 0003-commander-bridge-ipc-seam.patch 0004-commander-bridge-workspace.patch 0005-commander-panel-actions.patch 0006-commander-desktop-bootstrap-harness.patch 0007-commander-playwright-ui-fixture.patch 0008-commander-runtime-validation.patch 0009-commander-discoverable-entry.patch 0010-commander-global-titlebar.patch 0011-commander-global-command.patch 0012-commander-global-dialog.patch 0013-commander-dialog-command-void.patch 0014-commander-component-fixture-types.patch 0015-commander-isolated-sidecar-port.patch 0016-commander-global-overlay.patch 0017-commander-native-request-docks.patch 0018-commander-project-session-tools.patch 0019-commander-closed-overlay-status.patch 0020-commander-internal-navigation.patch 0021-commander-native-composer.patch 0022-commander-overlay-container-sizing.patch 0023-commander-overlay-viewport-bounds.patch 0024-commander-overlay-titlebar-clearance.patch 0025-commander-model-persistence.patch"

fail() {
  printf '%s\n' "prepare-opencode: $*" >&2
  exit 1
}

test "$#" -le 1 || fail "usage: $0 [/absolute/path/to/fresh-opencode-checkout]"

patch_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
source_root=$(CDPATH= cd -- "$patch_dir/.." && pwd)
repo_root=$(CDPATH= cd -- "$source_root/.." && pwd)
upstream=$(CDPATH= cd -- "${1:-$repo_root/local/opencode}" && pwd)
manifest="$patch_dir/bridge-source.sha256"
bundle="$upstream/packages/commander-bridge"
operator_example="$patch_dir/operator.env.example"
operator_launcher="$patch_dir/run-opencode-commander.sh"

test "$(git -C "$upstream" rev-parse --is-inside-work-tree 2>/dev/null || true)" = "true" || fail "target is not an OpenCode Git checkout"
test "$(git -C "$upstream" rev-parse HEAD)" = "$expected_revision" || fail "target must be OpenCode $expected_revision"
git -C "$upstream" diff --quiet || fail "target has unstaged changes"
git -C "$upstream" diff --cached --quiet || fail "target has staged changes"
test ! -e "$bundle" || fail "target already contains packages/commander-bridge"
test -f "$manifest" || fail "missing reviewed bridge manifest"
test -f "$operator_example" || fail "missing operator environment example"
test -f "$operator_launcher" || fail "missing operator launcher"

# The manifest is an allowlist: no README, project configuration, credentials, or
# untracked bridge files are copied into the maintained upstream build.
test -z "$(find "$source_root/bridge" -type l -print -quit)" || fail "bridge source must not contain symlinks"
expected_files=$(awk '{ print $2 }' "$manifest" | LC_ALL=C sort)
actual_files=$(cd "$source_root" && find bridge -type f \( -path 'bridge/package.json' -o -path 'bridge/tsconfig.json' -o -path 'bridge/src/*.ts' \) -print | LC_ALL=C sort)
test "$expected_files" = "$actual_files" || fail "bridge manifest does not exactly cover the reviewed bundle inputs"
(cd "$source_root" && shasum -a 256 -c "$manifest")

mkdir "$bundle"
while read -r digest relative_path; do
  case "$relative_path" in
    bridge/package.json|bridge/tsconfig.json|bridge/src/*.ts) ;;
    *) fail "manifest contains a disallowed path: $relative_path" ;;
  esac

  destination="$bundle/${relative_path#bridge/}"
  mkdir -p "$(dirname -- "$destination")"
  cp "$source_root/$relative_path" "$destination"
  test "$(shasum -a 256 "$destination" | awk '{ print $1 }')" = "$digest" || fail "copied digest differs: $relative_path"
done < "$manifest"

cp "$operator_example" "$upstream/commander.env.example"
cp "$operator_launcher" "$upstream/run-opencode-commander.sh"
chmod +x "$upstream/run-opencode-commander.sh"

for patch in $patch_names; do
  test -f "$patch_dir/$patch" || fail "missing patch $patch"
  git -C "$upstream" apply --allow-empty --check "$patch_dir/$patch"
  git -C "$upstream" apply --allow-empty "$patch_dir/$patch"
done

git -C "$upstream" diff --check
printf '%s\n' "Prepared OpenCode $expected_revision with the reviewed @digitaltwin/commander-bridge workspace package, commander.env.example, and run-opencode-commander.sh."

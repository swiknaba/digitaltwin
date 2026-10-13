#!/bin/sh

set -eu

readonly expected_revision="1f4d07a4a519185955ae8ab2ea3607805509e386"
readonly patch_names="0001-commander-gui-extension.patch 0002-commander-panel-safety.patch 0003-commander-bridge-ipc-seam.patch 0004-commander-bridge-workspace.patch 0005-commander-panel-actions.patch 0006-commander-desktop-bootstrap-harness.patch"

fail() {
  printf '%s\n' "prepare-opencode: $*" >&2
  exit 1
}

test "$#" -eq 1 || fail "usage: $0 /absolute/path/to/fresh-opencode-checkout"

patch_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
source_root=$(CDPATH= cd -- "$patch_dir/.." && pwd)
upstream=$(CDPATH= cd -- "$1" && pwd)
manifest="$patch_dir/bridge-source.sha256"
bundle="$upstream/packages/commander-bridge"

test "$(git -C "$upstream" rev-parse --is-inside-work-tree 2>/dev/null || true)" = "true" || fail "target is not an OpenCode Git checkout"
test "$(git -C "$upstream" rev-parse HEAD)" = "$expected_revision" || fail "target must be OpenCode $expected_revision"
git -C "$upstream" diff --quiet || fail "target has unstaged changes"
git -C "$upstream" diff --cached --quiet || fail "target has staged changes"
test ! -e "$bundle" || fail "target already contains packages/commander-bridge"
test -f "$manifest" || fail "missing reviewed bridge manifest"

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

for patch in $patch_names; do
  test -f "$patch_dir/$patch" || fail "missing patch $patch"
  git -C "$upstream" apply --check "$patch_dir/$patch"
  git -C "$upstream" apply "$patch_dir/$patch"
done

git -C "$upstream" diff --check
printf '%s\n' "Prepared OpenCode $expected_revision with the reviewed @digitaltwin/commander-bridge workspace package."

#!/bin/sh

set -eu

plugin_source=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/future-tasks.ts
plugin_directory=${OPENCODE_GLOBAL_PLUGIN_DIR:?Set OPENCODE_GLOBAL_PLUGIN_DIR to the operator-owned global plugin directory}
target="$plugin_directory/digitaltwin-future-tasks.ts"

test -f "$plugin_source"
mkdir -p "$plugin_directory"
test ! -e "$target" || test -L "$target"
ln -sfn "$plugin_source" "$target"
printf '%s\n' "Installed DigitalTwin future-tasks plugin link at $target"

#!/bin/sh

set -eu

plugin_root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
plugin_directory=${OPENCODE_GLOBAL_PLUGIN_DIR:?Set OPENCODE_GLOBAL_PLUGIN_DIR to the operator-owned global plugin directory}

mkdir -p "$plugin_directory"
for plugin_name in future-tasks commander-continuation; do
  plugin_source="$plugin_root/$plugin_name.ts"
  target="$plugin_directory/digitaltwin-$plugin_name.ts"
  test -f "$plugin_source"
  test ! -e "$target" || test -L "$target"
  ln -sfn "$plugin_source" "$target"
  printf '%s\n' "Installed DigitalTwin $plugin_name plugin link at $target"
done

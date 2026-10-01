#!/bin/sh
set -eu
[ "$(id -u)" -ne 0 ] || { echo 'Runtime must run as non-root' >&2; exit 1; }
umask 077
for path in "$HOME" /workspace /run/herdr; do
  [ -d "$path" ] && [ -w "$path" ] || { echo "Required volume is not writable: $path" >&2; exit 1; }
done
mkdir -p /workspace/repos /workspace/worktrees "$HOME/.config/herdr" "$HOME/.codex" "$HOME/.claude" "$HOME/.config/opencode"
if [ ! -e "$HOME/.config/herdr/config.toml" ]; then
  cp /opt/runtime/config/herdr.toml "$HOME/.config/herdr/config.toml"
fi
# Supported upstream installations preserve existing operator configuration.
for integration in codex claude opencode; do
  herdr integration install "$integration"
done
exec "$@"

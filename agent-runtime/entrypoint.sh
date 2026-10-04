#!/bin/sh
set -eu
[ "$(id -u)" -ne 0 ] || { echo 'Runtime must run as non-root' >&2; exit 1; }
umask 077
for path in "$HOME" /workspace /run/herdr; do
  [ -d "$path" ] && [ -w "$path" ] || { echo "Required volume is not writable: $path" >&2; exit 1; }
done
commander_workspace=/workspace/commander
hermes_home="$commander_workspace/.hermes"
mkdir -p "$commander_workspace" "$hermes_home" /workspace/repos /workspace/worktrees "$HOME/.config/herdr" "$HOME/.codex" "$HOME/.claude" "$HOME/.config/opencode"
for file in AGENTS.md .gitignore; do
  if [ ! -e "$commander_workspace/$file" ]; then
    cp "/opt/runtime/config/commander/$file" "$commander_workspace/$file"
  fi
done
if [ ! -d "$commander_workspace/.git" ]; then
  git -C "$commander_workspace" init -q
  git -C "$commander_workspace" config user.name "Digitaltwin Commander"
  git -C "$commander_workspace" config user.email "commander@localhost"
  git -C "$commander_workspace" add AGENTS.md .gitignore
  git -C "$commander_workspace" commit -qm "Initialize Commander workspace"
fi
if [ ! -e "$HOME/.config/herdr/config.toml" ]; then
  cp /opt/runtime/config/herdr.toml "$HOME/.config/herdr/config.toml"
fi
# Supported upstream installations preserve existing operator configuration.
for integration in codex claude opencode; do
  herdr integration install "$integration"
done
export HERMES_HOME="$hermes_home"
exec "$@"

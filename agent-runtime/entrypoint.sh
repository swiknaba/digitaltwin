#!/bin/sh
set -eu
[ "$(id -u)" -ne 0 ] || { echo 'Runtime must run as non-root' >&2; exit 1; }
umask 077
for path in "$HOME" /workspace /run/herdr; do
  [ -d "$path" ] && [ -w "$path" ] || { echo "Required volume is not writable: $path" >&2; exit 1; }
done
commander_workspace=/workspace/commander
hermes_home="$commander_workspace/.hermes"
grok_home="$HOME/.grok"
mkdir -p "$commander_workspace" "$hermes_home" /workspace/repos /workspace/worktrees "$HOME/.agents/skills" "$HOME/.config/herdr" "$HOME/.codex" "$HOME/.claude" "$HOME/.config/opencode" "$AGENTSVIEW_DATA_DIR" "$grok_home"
for file in AGENTS.md SOUL.md .gitignore; do
  if [ ! -e "$commander_workspace/$file" ]; then
    cp "/opt/runtime/config/commander/$file" "$commander_workspace/$file"
  fi
done
if [ ! -e "$hermes_home/config.yaml" ]; then
  cp /opt/runtime/config/commander/hermes-config.yaml "$hermes_home/config.yaml"
fi
# Existing Commander profiles are operator-owned. Merge the one managed shared
# library entry without replacing provider credentials or other preferences.
/opt/runtime/bin/ensure-hermes-shared-skills.py "$hermes_home/config.yaml"
if [ ! -d "$commander_workspace/.git" ]; then
  git -C "$commander_workspace" init -q
  git -C "$commander_workspace" config user.name "Digitaltwin Commander"
  git -C "$commander_workspace" config user.email "commander@localhost"
  git -C "$commander_workspace" add AGENTS.md SOUL.md .gitignore
  git -C "$commander_workspace" commit -qm "Initialize Commander workspace"
fi
if [ ! -e "$HOME/.config/herdr/config.toml" ]; then
  cp /opt/runtime/config/herdr.toml "$HOME/.config/herdr/config.toml"
fi
if [ ! -e "$grok_home/config.toml" ]; then
  cp /opt/runtime/config/grok/config.toml "$grok_home/config.toml"
fi
agentsview_config="$AGENTSVIEW_DATA_DIR/config.toml"
[ ! -L "$agentsview_config" ] || { echo 'AgentsView configuration must not be a symlink' >&2; exit 1; }
[ ! -e "$agentsview_config" ] || [ -f "$agentsview_config" ] || { echo 'AgentsView configuration must be a regular file' >&2; exit 1; }
# This runtime owns the aggregate-only AgentsView configuration. Replace it on
# each start so a persisted volume cannot add remote hosts, additional sources,
# or a UI listener. The usage archive itself is not replaced.
cp /opt/runtime/config/agentsview.toml "$agentsview_config"
chmod 600 "$agentsview_config"
# Supported upstream installations preserve existing operator configuration.
for integration in codex claude opencode grok; do
  herdr integration install "$integration"
done
export HERMES_HOME="$hermes_home"
exec "$@"

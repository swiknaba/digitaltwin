#!/bin/sh

set -eu

test "$#" -ge 2 || { printf '%s\n' "usage: $0 /path/to/commander.env opencode-command [args...]" >&2; exit 64; }

config=$1
shift

test -r "$config" || { printf '%s\n' "Commander operator environment is not readable: $config" >&2; exit 66; }

set -a
. "$config"
set +a

case ${DIGITALTWIN_COMMANDER_WORKSPACE:-} in
  /*) ;;
  *) printf '%s\n' "DIGITALTWIN_COMMANDER_WORKSPACE must be an absolute path" >&2; exit 78 ;;
esac

test -n "${DIGITALTWIN_COMMANDER_AGENT:-}" || { printf '%s\n' "DIGITALTWIN_COMMANDER_AGENT is required" >&2; exit 78; }
test -d "$DIGITALTWIN_COMMANDER_WORKSPACE" || { printf '%s\n' "Commander workspace does not exist: $DIGITALTWIN_COMMANDER_WORKSPACE" >&2; exit 78; }

exec "$@"

#!/bin/sh

set -eu

test "$#" -ge 2 || { printf '%s\n' "usage: $0 /path/to/commander.env opencode-command [args...]" >&2; exit 64; }

config=$1
shift

test -r "$config" || { printf '%s\n' "Commander operator environment is not readable: $config" >&2; exit 66; }
config_dir=$(CDPATH= cd -- "$(dirname -- "$config")" && pwd)

set -a
. "$config"
set +a

local_tmpdir=${DIGITALTWIN_LOCAL_TMPDIR:-"$config_dir/tmp"}
case "$local_tmpdir" in
  /*) ;;
  *) printf '%s\n' "DIGITALTWIN_LOCAL_TMPDIR must be an absolute path" >&2; exit 78 ;;
esac
mkdir -p "$local_tmpdir"
export TMPDIR="$local_tmpdir"
export DIGITALTWIN_LOCAL_TMPDIR="$local_tmpdir"

case ${DIGITALTWIN_COMMANDER_WORKSPACE:-} in
  /*) ;;
  *) printf '%s\n' "DIGITALTWIN_COMMANDER_WORKSPACE must be an absolute path" >&2; exit 78 ;;
esac

test -n "${DIGITALTWIN_COMMANDER_AGENT:-}" || { printf '%s\n' "DIGITALTWIN_COMMANDER_AGENT is required" >&2; exit 78; }
test -d "$DIGITALTWIN_COMMANDER_WORKSPACE" || { printf '%s\n' "Commander workspace does not exist: $DIGITALTWIN_COMMANDER_WORKSPACE" >&2; exit 78; }

exec "$@"

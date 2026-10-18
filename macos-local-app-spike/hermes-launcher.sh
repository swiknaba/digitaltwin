#!/bin/sh

set -eu

resource_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
export DIGITALTWIN_HERMES_SOURCE="$resource_root/hermes/source"
export PYTHONDONTWRITEBYTECODE=1

exec "$resource_root/hermes/runtime/python/bin/python3" -I -c 'import os, runpy, sys; sys.path.insert(0, os.environ["DIGITALTWIN_HERMES_SOURCE"]); sys.argv[0] = "hermes"; runpy.run_module("hermes_cli.main", run_name="__main__")' "$@"

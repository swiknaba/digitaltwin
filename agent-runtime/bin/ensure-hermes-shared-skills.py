#!/opt/hermes-agent/.venv/bin/python
"""Merge the Runtime's shared skill directory into an operator-owned Hermes config."""

import os
import stat
import sys
import tempfile
from pathlib import Path

import yaml


SHARED_SKILL_DIRECTORY = "/home/runtime/.agents/skills"


def main() -> int:
    path = Path(sys.argv[1])
    try:
        document = yaml.safe_load(path.read_text())
    except yaml.YAMLError as error:
        raise SystemExit(f"Invalid Commander Hermes config: {error}") from error
    if document is None:
        document = {}
    if not isinstance(document, dict):
        raise SystemExit("Commander Hermes config must be a mapping")

    skills = document.setdefault("skills", {})
    if not isinstance(skills, dict):
        raise SystemExit("Commander Hermes config skills must be a mapping")
    external_dirs = skills.setdefault("external_dirs", [])
    if not isinstance(external_dirs, list) or not all(isinstance(item, str) for item in external_dirs):
        raise SystemExit("Commander Hermes config skills.external_dirs must be a list of strings")
    if SHARED_SKILL_DIRECTORY in external_dirs:
        return 0

    external_dirs.append(SHARED_SKILL_DIRECTORY)
    mode = stat.S_IMODE(path.stat().st_mode)
    with tempfile.NamedTemporaryFile("w", dir=path.parent, prefix=f".{path.name}.", delete=False) as temporary:
        yaml.safe_dump(document, temporary, sort_keys=False)
        temporary_path = Path(temporary.name)
    os.chmod(temporary_path, mode)
    os.replace(temporary_path, path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Create deliberately empty, synthetic session roots for offline usage checks."""
import argparse
import json
from pathlib import Path
import tempfile


ROOTS = (
    ".claude/projects/fixture-project/session.jsonl",
    ".codex/sessions/2026/10/fixture.jsonl",
    ".gemini/tmp/fixture.json",
    ".local/share/opencode/fixture.json",
)
CONTENTS = {
    ROOTS[0]: '{"type":"fixture","entries":[]}\n',
    ROOTS[1]: '{"type":"fixture","items":[]}\n',
    ROOTS[2]: '{"session":"fixture","messages":[]}\n',
    ROOTS[3]: '{"session":"fixture","parts":[]}\n',
}
REPORTED_ZERO = {"status": "reported", "microdollars": 0}
FORBIDDEN_CONTENT = ("/users/", "/home/", "prompt", "secret", "credential")


def write_fixture(root: Path) -> dict[str, str]:
    root = root.resolve()
    created: dict[str, str] = {}
    for relative, content in CONTENTS.items():
        destination = root / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(content, encoding="utf-8")
        created[relative] = content
    return created


def self_test() -> None:
    with tempfile.TemporaryDirectory(prefix="agentsview-fixture-") as directory:
        root = Path(directory)
        created = write_fixture(root)
        assert tuple(created) == ROOTS
        assert all((root / relative).is_file() for relative in ROOTS)
        assert all(fragment not in content.lower() for content in created.values() for fragment in FORBIDDEN_CONTENT)
        assert REPORTED_ZERO == {"status": "reported", "microdollars": 0}
        assert not any(path.is_symlink() for path in root.rglob("*"))
    print("PASS: four synthetic AgentsView roots contain no session text or usable usage data")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--write-root", type=Path)
    arguments = parser.parse_args()
    if arguments.self_test:
        self_test()
    if arguments.write_root:
        created = write_fixture(arguments.write_root)
        print(json.dumps({"fixture_roots": list(created), "reported_zero": REPORTED_ZERO}, sort_keys=True))
    if not arguments.self_test and not arguments.write_root:
        parser.error("use --self-test or --write-root")


if __name__ == "__main__":
    main()

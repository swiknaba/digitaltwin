#!/usr/bin/env python3
"""Create synthetic usage-only session roots for offline AgentsView checks."""
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
SENTINEL_TRANSCRIPT = "TRANSCRIPT_SENTINEL_DO_NOT_ARCHIVE"
SENTINEL_CREDENTIAL = "CREDENTIAL_SENTINEL_DO_NOT_ARCHIVE"

CONTENTS = {
    ROOTS[0]: (
        '{"type":"user","uuid":"fixture-user","timestamp":"2026-10-04T12:00:00Z",'
        '"message":{"role":"user","content":"%s %s"}}\n'
        '{"type":"assistant","uuid":"fixture-assistant","timestamp":"2026-10-04T12:00:01Z",'
        '"message":{"role":"assistant","content":[{"type":"text","text":"%s"}],'
        '"usage":{"input_tokens":11,"output_tokens":13,"cache_creation_input_tokens":0,'
        '"cache_read_input_tokens":0}}}\n'
    ) % (SENTINEL_TRANSCRIPT, SENTINEL_CREDENTIAL, SENTINEL_TRANSCRIPT),
    ROOTS[1]: '{"type":"fixture","items":[]}\n',
    ROOTS[2]: '{"session":"fixture","messages":[]}\n',
    ROOTS[3]: '{"session":"fixture","parts":[]}\n',
}
REPORTED_ZERO = {"status": "reported", "microdollars": 0}
FORBIDDEN_CONTENT = ("/users/", "/home/")


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
        assert SENTINEL_TRANSCRIPT in created[ROOTS[0]]
        assert SENTINEL_CREDENTIAL in created[ROOTS[0]]
        assert REPORTED_ZERO == {"status": "reported", "microdollars": 0}
        assert not any(path.is_symlink() for path in root.rglob("*"))
    print("PASS: synthetic fixture includes recognized usage and isolated leak sentinels")


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

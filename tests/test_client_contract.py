"""Pinned stdlib client provenance and staging; no runtime/session effects."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent


class ClientContractTest(unittest.TestCase):
    def test_manifest_matches_frozen_backend_revision_and_docker_checks(self):
        manifest = json.loads((ROOT / "agent-runtime/contracts/kirei-clients.json").read_text())
        docker = (ROOT / "agent-runtime/Dockerfile").read_text()
        self.assertEqual(set(manifest["files"]), {
            "digitaltwin", "digitaltwin-mcp", "mcp.rb", "http_tools.rb",
            "agentsview_usage_response.rb", "agentsview_usage_authorizer.rb", "agentsview_usage_command.rb", "agentsview_usage_server.rb",
        })
        for name, item in manifest["files"].items():
            data = (ROOT / item["source"]).read_bytes()
            frozen = subprocess.run(["git", "show", manifest["source_revision"] + ":" + item["source"]], cwd=ROOT,
                                    check=True, stdout=subprocess.PIPE).stdout
            self.assertEqual(data, frozen)
            self.assertEqual(hashlib.sha256(data).hexdigest(), item["sha256"])
            self.assertIn(item["sha256"] + "  /usr/local/bin/" + name, docker)

    def test_client_pin_is_reachable_from_current_history(self):
        manifest = json.loads((ROOT / "agent-runtime/contracts/kirei-clients.json").read_text())
        result = subprocess.run(["git", "merge-base", "--is-ancestor", manifest["source_revision"], "HEAD"],
                                cwd=ROOT, capture_output=True)
        self.assertEqual(result.returncode, 0, "Client source revision must be retained in the checked-out history")

    def test_staging_rejects_modified_source_and_unexpected_context_files(self):
        manifest = json.loads((ROOT / "agent-runtime/contracts/kirei-clients.json").read_text())
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            paths = ["scripts/prepare-callback-context", "agent-runtime/contracts/kirei-clients.json"]
            paths += [item["source"] for item in manifest["files"].values()]
            for path in paths:
                target = root / path
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT / path, target)
            command = ["python3", str(root / "scripts/prepare-callback-context")]
            self.assertEqual(subprocess.run(command, capture_output=True).returncode, 0)
            context = root / ".local/kirei-clients"
            self.assertEqual({p.name for p in context.iterdir()}, set(manifest["files"]))
            (context / "unexpected").write_text("fixture")
            self.assertNotEqual(subprocess.run(command, capture_output=True).returncode, 0)
            (context / "unexpected").unlink()
            (root / "integration-backend/bin/digitaltwin").write_text("changed")
            self.assertNotEqual(subprocess.run(command, capture_output=True).returncode, 0)


if __name__ == "__main__":
    unittest.main()

"""Compose agreement checks only; these do not start or validate applications."""
import json
from pathlib import Path
import runpy
from types import SimpleNamespace
import unittest

ROOT = Path(__file__).resolve().parent.parent
acceptance = SimpleNamespace(**runpy.run_path(str(ROOT / "scripts/acceptance")))


class RootContractTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        command = acceptance.COMPOSE + ["-f", str(ROOT / "compose.yml"),
                                        "-f", str(ROOT / "compose.backend.yml"),
                                        "config", "--format", "json"]
        cls.services = json.loads(acceptance.run(command).stdout)["services"]

    def test_migrations_gate_each_backend_process(self):
        for name in ["backend-web", "backend-worker", "backend-chat-listener"]:
            self.assertEqual(self.services[name]["depends_on"]["backend-migrate"]["condition"],
                             "service_completed_successfully")

    def test_shared_image_and_nonroot_identity(self):
        for name in ["backend-migrate", "backend-web", "backend-worker", "backend-chat-listener"]:
            self.assertEqual(self.services[name]["image"], "digitaltwin-integration-backend:local")
            self.assertEqual(self.services[name]["user"], "10001:10001")
            self.assertNotIn("privileged", self.services[name])
            if name != "backend-worker":
                self.assertNotIn("volumes", self.services[name])

    def test_socket_stays_private_to_worker(self):
        worker = self.services["backend-worker"]
        self.assertEqual(worker["environment"]["HERDR_SOCKET_PATH"], "/run/herdr/herdr.sock")
        self.assertEqual(len(worker["volumes"]), 1)
        self.assertEqual(worker["volumes"][0]["type"], "volume")
        self.assertEqual(worker["volumes"][0]["source"], "herdr-socket")
        self.assertEqual(worker["volumes"][0]["target"], "/run/herdr")

    def test_local_exposure_and_independent_databases(self):
        for name in ["backend-web", "mattermost"]:
            self.assertEqual(self.services[name]["ports"][0]["host_ip"], "127.0.0.1")
        for name in ["postgres", "backend-worker", "backend-chat-listener", "backend-migrate"]:
            self.assertNotIn("ports", self.services[name])
        self.assertIn("@postgres:5432/digitaltwin_development", self.services["backend-web"]["environment"]["DATABASE_URL"])
        self.assertIn("@postgres:5432/mattermost?", self.services["mattermost"]["environment"]["MM_SQLSETTINGS_DATASOURCE"])

    def test_operator_mode_requires_no_docker_or_credentials(self):
        import contextlib
        import io
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            acceptance.operator()
        self.assertIn("this command starts nothing", output.getvalue())
        self.assertIn("real CLI", output.getvalue())


if __name__ == "__main__":
    unittest.main()

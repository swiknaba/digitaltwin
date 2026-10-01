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

    def test_stack_check_rejects_implicit_project(self):
        with self.assertRaisesRegex(RuntimeError, "explicit valid --project"):
            acceptance.stack(SimpleNamespace(project=None))

    def test_stack_check_requires_reviewed_runtime_name(self):
        with self.assertRaisesRegex(RuntimeError, "reviewed --runtime-service"):
            acceptance.stack(SimpleNamespace(project="test-stack", runtime_service=None))

    def test_server_status_rejects_incompatible_or_missing_health(self):
        for status in [{}, {"server": {"running": True, "version": "0.9.3", "protocol": 22, "compatible": False}},
                       {"server": {"running": True, "version": "0.9.3", "protocol": 23, "compatible": True}}]:
            with self.subTest(status=status), self.assertRaises(RuntimeError):
                acceptance.verify_herdr_status(status)


class CombinedRootContractTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        command = acceptance.COMPOSE + ["--profile", "push"]
        for name in ["compose.yml", "compose.backend.yml", "compose.integration.yml"]:
            command += ["-f", str(ROOT / name)]
        cls.services = json.loads(acceptance.run(command + ["config", "--format", "json"]).stdout)["services"]

    def test_runtime_is_private_and_nonroot(self):
        runtime = self.services["agent-runtime"]
        self.assertEqual(runtime["user"], "10001:10001")
        self.assertNotIn("ports", runtime)
        self.assertEqual(runtime["cap_drop"], ["ALL"])
        self.assertTrue(all(volume["type"] == "volume" for volume in runtime["volumes"]))
        self.assertEqual(runtime["build"]["target"], "with-callback")
        self.assertIn("kirei-clients", runtime["build"]["additional_contexts"])

    def test_worker_and_listener_wait_for_dependencies(self):
        self.assertEqual(self.services["backend-worker"]["depends_on"]["agent-runtime"]["condition"], "service_healthy")
        self.assertEqual(self.services["backend-chat-listener"]["depends_on"]["mattermost"]["condition"], "service_healthy")
        for name in ["backend-worker", "backend-chat-listener"]:
            self.assertEqual(self.services[name]["depends_on"]["backend-migrate"]["condition"], "service_completed_successfully")

    def test_chat_derived_build_and_disabled_credentials_features(self):
        chat = self.services["mattermost"]
        self.assertEqual(chat["user"], "2000:2000")
        self.assertEqual(chat["image"], "digitaltwin-chat-backend:local")
        self.assertTrue(chat["build"]["context"].endswith("/chat-backend"))
        self.assertEqual(chat["environment"]["MM_EMAILSETTINGS_SENDPUSHNOTIFICATIONS"], "false")
        self.assertEqual(chat["environment"]["MM_PLUGINSETTINGS_ENABLE"], "false")

    def test_only_initializer_requires_root_and_push_is_optional(self):
        initializer = self.services["local-volume-init"]
        self.assertEqual(initializer["user"], "0:0")
        self.assertEqual(initializer["network_mode"], "none")
        self.assertEqual(initializer["restart"], "no")
        for volume in initializer["volumes"]:
            if volume["type"] == "bind":
                self.assertTrue(volume["read_only"])
        push = self.services["push-proxy"]
        self.assertEqual(push["profiles"], ["push"])
        self.assertEqual(push["user"], "65534:65534")
        self.assertNotIn("ports", push)


if __name__ == "__main__":
    unittest.main()

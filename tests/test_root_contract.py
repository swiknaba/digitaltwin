"""OpenCode-first root configuration checks; these do not start applications."""
import contextlib
import io
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
        command = acceptance.COMPOSE + ["-f", str(ROOT / "compose.yml"), "config", "--format", "json"]
        cls.services = json.loads(acceptance.run(command).stdout)["services"]

    def test_default_stack_is_kirei_and_postgres_only(self):
        self.assertEqual(set(self.services), {"postgres", "backend-migrate", "backend-web", "backend-worker"})
        rendered = (ROOT / "compose.yml").read_text().lower()
        for retired in ["mattermost", "chat-listener", "push-proxy", "agent-runtime", "herdr"]:
            self.assertNotIn(retired, rendered)

    def test_backend_processes_wait_for_migrations_and_run_nonroot(self):
        for name in ["backend-web", "backend-worker"]:
            self.assertEqual(self.services[name]["depends_on"]["backend-migrate"]["condition"], "service_completed_successfully")
        for name in ["backend-migrate", "backend-web", "backend-worker"]:
            self.assertEqual(self.services[name]["image"], "digitaltwin-integration-backend:local")
            self.assertEqual(self.services[name]["user"], "10001:10001")
            self.assertNotIn("privileged", self.services[name])

    def test_only_web_is_published_on_loopback(self):
        self.assertEqual(self.services["backend-web"]["ports"][0]["host_ip"], "127.0.0.1")
        for name in ["postgres", "backend-migrate", "backend-worker"]:
            self.assertNotIn("ports", self.services[name])

    def test_database_bootstrap_has_no_chat_role_or_database(self):
        bootstrap = (ROOT / "scripts/init-postgres.sh").read_text().lower()
        self.assertIn("create role kirei", bootstrap)
        self.assertIn("create database digitaltwin_development", bootstrap)
        self.assertNotIn("mattermost", bootstrap)
        self.assertNotIn("mattermost", (ROOT / ".env.example").read_text().lower())

    def test_default_worker_dispatches_only_future_tasks(self):
        worker = (ROOT / "integration-backend/bin/worker").read_text().lower()
        handlers = (ROOT / "integration-backend/app/services/job_handlers.rb").read_text()
        kinds = (ROOT / "integration-backend/app/platform/jobs/dto/job_kind.rb").read_text()
        self.assertIn("services::jobhandlers", worker)
        self.assertIn("FutureTaskDue", handlers)
        self.assertEqual(kinds.count(" = new("), 1)
        self.assertNotIn("local_dispatch_preflight", worker)
        self.assertNotIn("mattermostpost", worker)
        self.assertNotIn("sessions::renewals", worker)

    def test_operator_mode_is_non_mutating_and_names_remaining_boundaries(self):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            acceptance.operator()
        value = output.getvalue()
        self.assertIn("this command starts nothing", value)
        self.assertIn("Commander runtime identity", value)
        self.assertIn("No Mattermost", value)


if __name__ == "__main__":
    unittest.main()

"""Compose agreement checks only; these do not start or validate applications."""
import json
import os
from pathlib import Path
import runpy
import subprocess
import tempfile
from types import SimpleNamespace
import unittest

ROOT = Path(__file__).resolve().parent.parent
acceptance = SimpleNamespace(**runpy.run_path(str(ROOT / "scripts/acceptance")))


class RootContractTest(unittest.TestCase):
    def test_local_compose_uses_a_stable_project_and_reclaims_rebuilt_images(self):
        compose = (ROOT / "compose.yml").read_text()
        dev = (ROOT / "scripts/dev").read_text()

        self.assertIn("name: digitaltwin\n", compose)
        self.assertNotIn("up --build", dev)
        self.assertIn(
            "docker image prune -f --filter dangling=true "
            "--filter label=com.docker.compose.project=digitaltwin",
            dev,
        )

    @classmethod
    def setUpClass(cls):
        command = acceptance.COMPOSE + ["--profile", "chat-validation", "-f", str(ROOT / "compose.yml"),
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
            if name in ["backend-migrate", "backend-web"]:
                self.assertNotIn("volumes", self.services[name])

    def test_socket_stays_private_to_worker(self):
        worker = self.services["backend-worker"]
        self.assertEqual(worker["environment"]["HERDR_SOCKET_PATH"], "/run/herdr/herdr.sock")
        self.assertEqual(len(worker["volumes"]), 2)
        self.assertEqual(worker["volumes"][0]["type"], "volume")
        self.assertEqual(worker["volumes"][0]["source"], "herdr-socket")
        self.assertEqual(worker["volumes"][0]["target"], "/run/herdr")
        self.assertEqual(worker["volumes"][1]["source"], "runtime-workspace")
        self.assertEqual(worker["volumes"][1]["target"], "/workspace")

    def test_nonweb_roles_override_image_web_probe(self):
        for service, role in [("backend-worker", "worker"), ("backend-chat-listener", "chat-listener")]:
            self.assertEqual(self.services[service]["healthcheck"]["test"], ["CMD", "bin/health", role])

    def test_listener_requires_opt_in_and_worker_validation_stays_closed(self):
        self.assertEqual(self.services["backend-chat-listener"]["profiles"], ["chat-validation"])
        self.assertEqual(self.services["backend-chat-listener"]["environment"]["CHAT_VALIDATION_MODE"], "1")
        self.assertEqual(self.services["backend-worker"]["environment"]["CHAT_VALIDATION_MODE"], "0")
        command = acceptance.COMPOSE + ["-f", str(ROOT / "compose.yml"),
                                        "-f", str(ROOT / "compose.backend.yml"), "config", "--services"]
        self.assertNotIn("backend-chat-listener", acceptance.run(command).stdout.splitlines())

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
    def test_local_activation_supplies_all_processes_with_the_chat_address(self):
        environment = {**os.environ, "MATTERMOST_CHANNEL_IDS": "fixture-channel",
                       "MATTERMOST_COMMANDER_BOT_ID": "fixture-commander", "MATTERMOST_AGENT_BOT_ID": "fixture-agent"}
        command = ["docker", "compose", "--env-file", str(ROOT / ".env.example"), "--profile", "chat-validation",
                   "-f", str(ROOT / "compose.yml"), "-f", str(ROOT / "compose.local-commander.yml"), "config", "--format", "json"]
        result = subprocess.run(command, cwd=ROOT, env=environment, check=True, capture_output=True, text=True)
        services = json.loads(result.stdout)["services"]
        for name in ["backend-web", "backend-worker", "backend-chat-listener"]:
            self.assertEqual(services[name]["environment"]["MATTERMOST_URL"], "http://mattermost:8065")

    @classmethod
    def setUpClass(cls):
        command = acceptance.COMPOSE + ["--profile", "*"]
        for name in ["compose.yml", "compose.backend.yml", "compose.integration.yml"]:
            command += ["-f", str(ROOT / name)]
        cls.services = json.loads(acceptance.run(command + ["config", "--format", "json"]).stdout)["services"]

    def test_plain_compose_selects_complete_credential_free_core(self):
        command = acceptance.COMPOSE + ["-f", str(ROOT / "compose.yml"), "config", "--services"]
        self.assertEqual(set(acceptance.run(command).stdout.splitlines()),
                         {"postgres", "mattermost", "local-volume-init", "backend-migrate", "backend-web", "backend-worker", "agent-runtime"})

    def test_runtime_exposes_only_the_local_codex_login_callback_and_runs_nonroot(self):
        runtime = self.services["agent-runtime"]
        self.assertEqual(runtime["user"], "10001:10001")
        self.assertEqual(len(runtime["ports"]), 1)
        self.assertEqual(runtime["ports"][0]["host_ip"], "127.0.0.1")
        self.assertEqual(runtime["ports"][0]["published"], "1455")
        self.assertEqual(runtime["ports"][0]["target"], 1455)
        self.assertEqual(runtime["ports"][0]["protocol"], "tcp")
        self.assertEqual(runtime["cap_drop"], ["ALL"])
        self.assertTrue(all(volume["type"] == "volume" for volume in runtime["volumes"]))
        self.assertEqual(runtime["build"]["target"], "with-callback")
        self.assertIn("kirei-clients", runtime["build"]["additional_contexts"])

    def test_hermes_mcp_template_is_tracked(self):
        template = "agent-runtime/config/commander/hermes-config.yaml"
        subprocess.run(["git", "ls-files", "--error-unmatch", template], cwd=ROOT, check=True,
                       stdout=subprocess.DEVNULL)
        configuration = (ROOT / template).read_text()
        self.assertIn("digitaltwin-mcp", configuration)

    def test_runtime_provision_forwards_an_optional_company_subdirectory(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            executable = root / "wagglebot"
            captured = root / "arguments"
            executable.write_text('#!/bin/sh\nprintf "%s\\n" "$@" > "$CAPTURED_ARGUMENTS"\n')
            executable.chmod(0o755)
            environment = {**os.environ, "PATH": f"{root}:{os.environ['PATH']}", "CAPTURED_ARGUMENTS": str(captured)}
            subprocess.run([str(ROOT / "agent-runtime/bin/runtime-provision"), "connect", "https://example.invalid/company.git",
                            "examples/reference-setup"], check=True, env=environment)
            self.assertEqual(captured.read_text().splitlines(), ["connect", "https://example.invalid/company.git", "examples/reference-setup"])

    def test_worker_and_listener_wait_for_dependencies(self):
        self.assertEqual(self.services["backend-worker"]["depends_on"]["agent-runtime"]["condition"], "service_healthy")
        self.assertEqual(self.services["backend-chat-listener"]["depends_on"]["agent-runtime"]["condition"], "service_healthy")
        self.assertEqual(self.services["backend-chat-listener"]["depends_on"]["mattermost"]["condition"], "service_healthy")
        for name in ["backend-worker", "backend-chat-listener"]:
            self.assertEqual(self.services[name]["depends_on"]["backend-migrate"]["condition"], "service_completed_successfully")

    def test_listener_receives_the_required_private_herdr_socket(self):
        listener = self.services["backend-chat-listener"]
        self.assertEqual(len(listener["volumes"]), 1)
        self.assertEqual(listener["volumes"][0]["type"], "volume")
        self.assertEqual(listener["volumes"][0]["source"], "herdr-socket")
        self.assertEqual(listener["volumes"][0]["target"], "/run/herdr")

    def test_chat_derived_build_and_disabled_credentials_features(self):
        chat = self.services["mattermost"]
        self.assertEqual(chat["user"], "2000:2000")
        self.assertEqual(chat["image"], "digitaltwin-chat-backend:local")
        self.assertTrue(chat["build"]["context"].endswith("/chat-backend"))
        self.assertEqual(chat["environment"]["MM_EMAILSETTINGS_SENDPUSHNOTIFICATIONS"], "false")
        self.assertEqual(chat["environment"]["MM_PLUGINSETTINGS_ENABLE"], "false")
        self.assertEqual(chat["environment"]["MM_SERVICESETTINGS_ENABLEBOTACCOUNTCREATION"], "true")
        self.assertEqual(chat["environment"]["MM_SERVICESETTINGS_ENABLEUSERACCESSTOKENS"], "true")

    def test_local_chat_supports_the_named_commander_and_agent_setup(self):
        phase0 = json.loads((ROOT / "chat-backend/config/phase0.json").read_text())
        self.assertTrue(phase0["ServiceSettings"]["EnableBotAccountCreation"])
        self.assertTrue(phase0["ServiceSettings"]["EnableUserAccessTokens"])

        activation = (ROOT / "compose.local-commander.yml").read_text()
        self.assertIn("MATTERMOST_COMMANDER_BOT_ID", activation)
        self.assertIn("MATTERMOST_COMMANDER_TOKEN_FILE", activation)
        self.assertIn("/local-config/commander.token", activation)
        self.assertIn("MATTERMOST_AGENT_BOT_ID", activation)
        self.assertIn("MATTERMOST_AGENT_TOKEN_FILE", activation)
        self.assertIn("/local-config/agent.token", activation)
        self.assertIn('source: "./.local/commander"', activation)
        self.assertNotIn("DIGITALTWIN_LOCAL_CONFIG_DIR", activation)
        self.assertNotIn("MATTERMOST_LOCAL_BOT_IDS", activation)
        self.assertNotIn("MATTERMOST_PEER_BOT_IDS", activation)
        self.assertNotIn("MATTERMOST_WORKER_", activation)
        self.assertNotIn("/local-config/worker.token", activation)

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


class CiWorkflowContractTest(unittest.TestCase):
    def test_fast_contracts_are_split_by_monorepo_component(self):
        workflow = (ROOT / ".github/workflows/full-stack.yml").read_text()
        self.assertNotIn("Fast source contract checks", workflow)
        self.assertIn("name: Client Runtime contract", workflow)
        self.assertIn("run: python3 -m unittest tests.test_client_contract -v", workflow)
        self.assertIn("name: Chat Backend contract", workflow)
        self.assertIn("run: python3 -m unittest discover -s chat-backend/tests -v", workflow)
        self.assertIn("name: Root Compose contract", workflow)
        self.assertIn("run: python3 -m unittest tests.test_root_contract -v", workflow)


if __name__ == "__main__":
    unittest.main()

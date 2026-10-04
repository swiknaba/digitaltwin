"""Opt-in real local containers; synthetic callbacks are never provider evidence."""
import concurrent.futures
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time
import unittest
import urllib.error
import urllib.request
import uuid

ROOT = Path(__file__).resolve().parent.parent
ENV = {k: v for k, v in os.environ.items() if not k.startswith(("COMPOSE_", "DOCKER_")) and k not in
       {"POSTGRES_PASSWORD", "KIREI_DB_PASSWORD", "MATTERMOST_DB_PASSWORD", "BACKEND_PORT"}}
CALLBACK_SHA = json.loads((ROOT / "agent-runtime/contracts/kirei-clients.json").read_text())["files"]["digitaltwin"]["sha256"]
EXPECTED_MIGRATION_VERSION = max(int(path.name.split("_", 1)[0]) for path in (ROOT / "integration-backend/db/migrate").glob("[0-9][0-9][0-9]_*.rb"))


@unittest.skipUnless(os.getenv("DIGITALTWIN_RUN_COMPOSE_TESTS") == "1", "explicit disposable Compose opt-in required")
class DisposableComposeTest(unittest.TestCase):
    @classmethod
    def command(cls, args, *, source=None, timeout=180, check=True):
        try:
            result = subprocess.run(args, cwd=ROOT, env=ENV, input=source, text=True,
                                    capture_output=True, timeout=timeout)
        except subprocess.TimeoutExpired as error:
            diagnostic = error.stderr or ""
            if isinstance(diagnostic, bytes):
                diagnostic = diagnostic.decode(errors="replace")
            for marker in ["local-only-postgres", "local-only-kirei", "local-only-mattermost"]:
                diagnostic = diagnostic.replace(marker, "<sample-redacted>")
            diagnostic = re.sub(r"(postgres(?:ql)?://)[^@\s]+@", r"\1<redacted>@", diagnostic)
            raise RuntimeError(f"local command timed out after {timeout}s: {args[0:2]}\n{diagnostic[-3000:]}") from error
        if check and result.returncode:
            # Service logs/config may contain credentials. Keep failure output sanitized.
            diagnostic = result.stderr[-3000:]
            for marker in ["local-only-postgres", "local-only-kirei", "local-only-mattermost"]:
                diagnostic = diagnostic.replace(marker, "<sample-redacted>")
            diagnostic = re.sub(r"(postgres(?:ql)?://)[^@\s]+@", r"\1<redacted>@", diagnostic)
            raise RuntimeError(f"local command failed, exit {result.returncode}: {args[0:2]}\n{diagnostic}")
        return result

    @classmethod
    def compose(cls, args, **kwargs):
        return cls.command(cls.base + args, **kwargs)

    @classmethod
    def setUpClass(cls):
        revision = os.environ.get("DIGITALTWIN_REVIEWED_BACKEND_REVISION")
        if not revision or not re.fullmatch(r"[0-9a-f]{40}", revision):
            raise RuntimeError("exact reviewed merged backend revision required")
        cls.command(["git", "merge-base", "--is-ancestor", revision, "HEAD"])
        if not (ROOT / "integration-backend/Dockerfile").is_file():
            raise RuntimeError("reviewed backend must be integrated first")
        context = json.loads(cls.command(["docker", "context", "inspect"]).stdout)
        if len(context) != 1 or not context[0]["Endpoints"]["docker"]["Host"].startswith("unix://"):
            raise RuntimeError("suite requires a local Unix Docker endpoint; remote infrastructure is excluded")
        cls.project = "digitaltwin-integration-" + uuid.uuid4().hex[:12]
        cls.temporary = tempfile.TemporaryDirectory(prefix=cls.project)
        cls.addClassCleanup(cls.temporary.cleanup)
        override = Path(cls.temporary.name) / "compose.yml"
        override.write_text(f'''services:
  mattermost:
    image: {cls.project}-chat:check
    ports: !override
      - "127.0.0.1::8065"
  backend-migrate:
    image: {cls.project}-backend:check
  backend-web:
    image: {cls.project}-backend:check
    ports: !override
      - "127.0.0.1::3000"
  backend-worker:
    image: {cls.project}-backend:check
  agent-runtime:
    image: {cls.project}-runtime:check
''')
        cls.base = ["docker", "compose", "--env-file", str(ROOT / ".env.example"), "-p", cls.project]
        for name in [ROOT / "compose.yml", ROOT / "compose.backend.yml", ROOT / "compose.integration.yml", override]:
            cls.base += ["-f", str(name)]
        cls.addClassCleanup(cls.cleanup)
        cls.command([str(ROOT / "scripts/prepare-callback-context")])
        cls.compose(["config", "--quiet"])
        cls.compose(["build", "mattermost", "backend-web", "agent-runtime"], timeout=1800)
        try:
            cls.compose(["up", "-d", "--no-build", "--pull", "never", "--wait", "--wait-timeout", "240"], timeout=300)
        except RuntimeError as error:
            # Fresh disposable stack contains only checked-in public DB samples.
            state = cls.compose(["ps", "--all", "--format", "json"], check=False)
            diagnostic = cls.compose(["logs", "--no-color", "--tail", "30", "postgres", "local-volume-init", "backend-migrate", "backend-web", "backend-worker", "agent-runtime", "mattermost"], check=False)
            # Keep the failing service's own output before verbose Compose state.
            # The raised diagnostic is deliberately bounded below, and the state
            # records can otherwise hide the only actionable startup error.
            detail = "Service logs:\n" + diagnostic.stdout + diagnostic.stderr + "\nContainer states:\n" + state.stdout + state.stderr
            for marker in ["local-only-postgres", "local-only-kirei", "local-only-mattermost"]:
                detail = detail.replace(marker, "<sample-redacted>")
            detail = re.sub(r"(postgres(?:ql)?://)[^@\s]+@", r"\1<redacted>@", detail)
            raise RuntimeError(str(error) + "\nDisposable migration/startup diagnostic:\n" + detail[:5000]) from None
        cls.refresh_addresses()
        cls.evidence = {"revision": cls.command(["git", "rev-parse", "HEAD"]).stdout.strip(),
                        "reviewed_backend_revision": revision, "live_local_containers": True,
                        "synthetic_callbacks": True, "authenticated_chat": False,
                        "provider_cli": False, "commander_mcp": False, "phase0_acceptance": False,
                        "image_ids": {}}

    @classmethod
    def refresh_addresses(cls):
        # Docker can allocate a new random host port when restarting a container.
        cls.addresses = {}
        for service, port in [("backend-web", "3000"), ("mattermost", "8065")]:
            address = cls.compose(["port", service, port]).stdout.strip()
            if not address.startswith("127.0.0.1:") or "\n" in address:
                raise RuntimeError("expected one disposable loopback port")
            cls.addresses[service] = "http://" + address

    @classmethod
    def cleanup(cls):
        result = cls.compose(["down", "--volumes", "--remove-orphans"], check=False)
        # Only uniquely tagged images from this run; no other workers' artifacts.
        cls.command(["docker", "image", "rm", *[f"{cls.project}-{s}:check" for s in ["chat", "backend", "runtime"]]], check=False)
        if result.returncode:
            raise RuntimeError(f"cleanup failed for own project {cls.project}")
        label = "label=com.docker.compose.project=" + cls.project
        for args in [["docker", "ps", "-aq", "--filter", label],
                     ["docker", "volume", "ls", "-q", "--filter", label],
                     ["docker", "network", "ls", "-q", "--filter", label]]:
            if cls.command(args).stdout.strip():
                raise RuntimeError(f"own project resources remain: {cls.project}")
        if hasattr(cls, "evidence"):
            cls.evidence["own_resources_removed"] = True
            print(json.dumps(cls.evidence, sort_keys=True))

    @classmethod
    def ruby(cls, source, **kwargs):
        return cls.compose(["exec", "-T", "backend-web", "bundle", "exec", "ruby", "-r", "./app", "-"], source=source, **kwargs)

    def get(self, service, path):
        with urllib.request.urlopen(self.addresses[service] + path, timeout=10) as response:
            return response.status, json.load(response), response.headers

    def test_01_health_migrations_database_ownership(self):
        running = self.compose(["ps", "--services", "--status", "running"]).stdout.splitlines()
        self.assertNotIn("backend-chat-listener", running)
        self.assertNotIn("push-proxy", running)
        for path in ["/livez", "/readyz"]:
            self.assertEqual(self.get("backend-web", path)[0], 200)
        _, body, headers = self.get("mattermost", "/api/v4/system/ping")
        self.assertEqual(body["status"], "OK")
        self.assertTrue(headers.get("X-Version-Id", "").startswith("11.11.1"))
        with urllib.request.urlopen(self.addresses["mattermost"] + "/", timeout=10) as response:
            self.assertEqual(response.status, 200)
            self.assertIn("text/html", response.headers.get("Content-Type", ""))
            self.assertIn(b"<html", response.read(1048576).lower())
        self.ruby(f"abort 'migrations' unless Kirei::App.raw_db_connection[:schema_info].get(:version) == {EXPECTED_MIGRATION_VERSION}")
        for user, password, database, other in [
            ("kirei", "local-only-kirei", "digitaltwin_development", "mattermost"),
            ("mattermost", "local-only-mattermost", "mattermost", "digitaltwin_development")]:
            args = ["exec", "-T", "-e", "PGPASSWORD=" + password, "postgres", "psql", "-h", "127.0.0.1", "-U", user, "-At", "-d"]
            self.assertEqual(self.compose(args + [database, "-c", "SELECT current_user"]).stdout.strip(), user)
            denied = self.compose(args + [other, "-c", "SELECT 1"], check=False)
            self.assertNotEqual(denied.returncode, 0)
            self.assertIn("permission denied for database", denied.stderr)
        self.evidence["database_ownership_and_migrations"] = True

    def test_02_container_uid_socket_callback_and_plugin_boundary(self):
        socket = "s=File.stat('/run/herdr/herdr.sock'); abort unless Process.uid==10001 && s.socket? && s.uid==10001 && (s.mode & 0777)==0600"
        for service in ["agent-runtime", "backend-worker"]:
            self.compose(["exec", "-T", service, "ruby", "-e", socket])
        status = json.loads(self.compose(["exec", "-T", "agent-runtime", "herdr", "status", "--json"]).stdout)["server"]
        self.assertEqual((status["running"], status["compatible"], status["version"], status["protocol"]),
                         (True, True, "0.9.3", 22))
        self.compose(["exec", "-T", "agent-runtime", "ruby", "-rdigest", "-e",
                      f"abort unless Digest::SHA256.file('/usr/local/bin/digitaltwin').hexdigest=='{CALLBACK_SHA}'"])
        for service in ["agent-runtime", "backend-web", "backend-worker", "mattermost"]:
            container = self.compose(["ps", "-q", service]).stdout.strip()
            inspect = json.loads(self.command(["docker", "inspect", container]).stdout)[0]
            self.evidence["image_ids"][service] = inspect["Image"]
            self.assertFalse(inspect["HostConfig"]["Privileged"])
            self.assertNotIn("0", inspect["Config"]["User"].split(":"))
            for mount in inspect["Mounts"]:
                self.assertNotEqual(mount["Destination"], "/")
                self.assertNotIn("docker.sock", mount["Destination"])
            if service == "agent-runtime":
                self.assertEqual(inspect["HostConfig"]["CapDrop"], ["ALL"])
                self.assertFalse(inspect["HostConfig"]["PortBindings"])
        # Distroless chat has no shell. Inspect its container filesystem metadata.
        chat = self.compose(["ps", "-q", "mattermost"]).stdout.strip()
        import tarfile
        archive = Path(self.temporary.name) / "chat.tar"
        with archive.open("wb") as stream:
            result = subprocess.run(["docker", "export", chat], env=ENV, stdout=stream, stderr=subprocess.PIPE)
        self.assertEqual(result.returncode, 0)
        with tarfile.open(archive) as files:
            plugins = [n for n in files.getnames() if n.startswith(("mattermost/prepackaged_plugins/", "mattermost/plugins/", "mattermost/client/plugins/"))]
        archive.unlink()
        self.assertEqual(plugins, [])
        self.evidence["container_security_socket_callback_hash_no_plugins"] = True

    def test_03_falcon_parallel_http_and_rejected_json(self):
        with concurrent.futures.ThreadPoolExecutor(max_workers=10) as pool:
            responses = list(pool.map(lambda _: self.get("backend-web", "/readyz"), range(30)))
            self.assertEqual([response[0] for response in responses], [200] * 30)
            self.assertEqual(len({response[2].get("X-Request-Id") for response in responses}), 30)
        for data, status in [(b'{"generation":1,"key":"fixture","text":"synthetic"}', 401),
                             (b'{"channel_id":"forged"}', 400), (b'{', 400), (b'[]', 400), (b'x' * 65537, 413)]:
            request = urllib.request.Request(self.addresses["backend-web"] + "/internal/callbacks/say", data=data,
                                             headers={"Content-Type": "application/json"})
            with self.assertRaises(urllib.error.HTTPError) as rejected:
                urllib.request.urlopen(request, timeout=10)
            self.assertEqual(rejected.exception.code, status)
        self.evidence["falcon_parallel_health_and_callback_auth_rejection"] = True

    def test_04_durable_jobs_and_restart(self):
        self.compose(["stop", "backend-worker"])
        fixture = (ROOT / "tests/fixtures/durable_state.rb").read_text()
        self.ruby(fixture)
        self.compose(["restart", "backend-web", "agent-runtime"])
        self.compose(["up", "-d", "--no-build", "--wait", "--wait-timeout", "120", "backend-web", "agent-runtime", "backend-worker"], timeout=180)
        self.refresh_addresses()
        self.assertEqual(self.get("backend-web", "/readyz")[0], 200)
        deadline = time.monotonic() + 20
        while True:
            checked = self.ruby("db=Kirei::App.raw_db_connection; abort unless db[:jobs][dispatch_key:'integration:blocked'][:status]=='blocked' && db[:jobs][dispatch_key:'integration:uncertain'][:status]=='uncertain'", check=False)
            if checked.returncode == 0:
                break
            if time.monotonic() > deadline:
                self.fail("worker did not block fixture job after restart")
            time.sleep(0.5)
        self.evidence["synthetic_jobs_dedup_leases_uncertain_restart"] = True

    def test_05_packaged_callback_synthetic_thread_binding(self):
        self.ruby((ROOT / "tests/fixtures/callback_state.rb").read_text())
        token_file = "/tmp/integration-fixture-token"
        try:
            for index in [1, 2]:
                self.compose(["exec", "-T", "agent-runtime", "ruby", "-e",
                              f"File.write('{token_file}', 'synthetic-integration-{index}', mode: 'w', perm: 0600)"])
                callback = ["exec", "-T", "-e", "DIGITALTWIN_SESSION_TOKEN_FILE=" + token_file,
                            "-e", "DIGITALTWIN_SESSION_GENERATION=1", "-e", "DIGITALTWIN_CALLBACK_URL=http://backend-web:3000",
                            "agent-runtime", "digitaltwin", "say", "--text", "fixture question", "--key", "same-key"]
                for _ in range(2):
                    self.compose(callback)
                changed = callback.copy()
                changed[changed.index("fixture question")] = "changed fixture"
                self.assertNotEqual(self.compose(changed, check=False).returncode, 0)
                stale = callback.copy()
                stale[stale.index("DIGITALTWIN_SESSION_GENERATION=1")] = "DIGITALTWIN_SESSION_GENERATION=2"
                self.assertNotEqual(self.compose(stale, check=False).returncode, 0)
            self.ruby("db=Kirei::App.raw_db_connection; rows=db[:outbox].where(Sequel.like(:response_key,'callback:integration:%')).all; abort unless rows.size==2 && rows.map{|r| [r[:channel_id],r[:thread_id],r[:bot],r[:role]]}.sort==[['fixture-channel','fixture-root-1','worker','writer'],['fixture-channel','fixture-root-2','worker','writer']]")
        finally:
            self.compose(["exec", "-T", "agent-runtime", "ruby", "-e", f"File.unlink('{token_file}') if File.exist?('{token_file}')"])
            self.ruby("db=Kirei::App.raw_db_connection; db[:sessions].where(Sequel.like(:id,'integration:%')).update(active:false,credential_expires_at:Time.now-1)")
        self.evidence["synthetic_packaged_callback_two_threads_replay_changed_body"] = True

    def test_06_pending_migrations_fail_closed_and_pool_bounds(self):
        self.ruby((ROOT / "tests/fixtures/pool_bounds.rb").read_text())
        self.ruby(f"db=Kirei::App.raw_db_connection; abort unless db.pool.max_size==5 && db.opts[:pool_timeout].to_f==2; db[:schema_info].update(version:{EXPECTED_MIGRATION_VERSION - 1})")
        try:
            startup = self.compose(["run", "--rm", "--no-deps", "-e", "BOOT_CHECK_ONLY=1", "backend-web", "bin/web"], check=False)
            self.assertNotEqual(startup.returncode, 0)
            self.assertIn("Pending migrations", startup.stderr)
        finally:
            self.ruby(f"Kirei::App.raw_db_connection[:schema_info].update(version:{EXPECTED_MIGRATION_VERSION})")
        self.assertEqual(self.get("backend-web", "/readyz")[0], 200)
        self.evidence["pending_migrations_rejected_pool_5_timeout_2"] = True


if __name__ == "__main__":
    unittest.main(verbosity=2)

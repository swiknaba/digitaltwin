import json
import os
from pathlib import Path
import shutil
import socket
import sqlite3
import subprocess
import sys
import tempfile
import unittest


REPOSITORY = Path(__file__).resolve().parents[1]
LAUNCHER_SOURCE = REPOSITORY / "macos-local-app-spike" / "launcher.sh"
WORK_ROOT = REPOSITORY / "local" / "tmp"


class MacosLocalAppSpikeLauncherTest(unittest.TestCase):
    def test_launch_passes_the_ephemeral_adapter_token_and_only_the_active_native_anthropic_key(self):
        with self._temporary_root() as temporary:
            root = Path(temporary)
            active = self._launch(root, active_credential=True)
            self.assertEqual((active / "opencode-adapter-token").read_text(), "present")
            self.assertEqual((active / "hermes-anthropic-key").read_text(), "present")
            self.assertEqual((active / "adapter-anthropic-key").read_text(), "absent")

            inactive = self._launch(root, active_credential=False)
            self.assertEqual((inactive / "opencode-adapter-token").read_text(), "present")
            self.assertEqual((inactive / "hermes-anthropic-key").read_text(), "absent")
            self.assertEqual((inactive / "adapter-anthropic-key").read_text(), "absent")

    def _launch(self, root: Path, active_credential: bool) -> Path:
        label = "active" if active_credential else "inactive"
        app = root / label / "DigitalTwin.app"
        resources = app / "Contents" / "Resources"
        records = root / label / "records"
        data = root / label / "data"
        launcher = app / "Contents" / "MacOS" / "DigitalTwin"
        records.mkdir(parents=True)
        launcher.parent.mkdir(parents=True)
        shutil.copy2(LAUNCHER_SOURCE, launcher)
        launcher.chmod(0o755)
        self._write_resources(resources)
        self._write_credential(data, active_credential)
        ports = self._ports(5)
        environment = os.environ.copy()
        environment.pop("ANTHROPIC_API_KEY", None)
        environment.update(
            {
                "DIGITALTWIN_APP_DATA_ROOT": str(data),
                "DIGITALTWIN_APP_POSTGRES_PORT": str(ports[0]),
                "DIGITALTWIN_APP_WEB_PORT": str(ports[1]),
                "DIGITALTWIN_APP_HERMES_PORT": str(ports[2]),
                "DIGITALTWIN_APP_ADAPTER_PORT": str(ports[3]),
                "DIGITALTWIN_APP_OPENCODE_PORT": str(ports[4]),
                "DIGITALTWIN_TEST_RECORD_DIR": str(records),
                "DIGITALTWIN_TEST_PYTHON": sys.executable,
            }
        )
        result = subprocess.run([str(launcher), "launch"], env=environment, timeout=30, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        return records

    def _write_resources(self, resources: Path) -> None:
        self._executable(resources / "OpenCode.app" / "Contents" / "MacOS" / "OpenCode Dev", """#!/bin/sh
if test -n \"${DIGITALTWIN_HERMES_ADAPTER_TOKEN:-}\"; then
  printf present > \"$DIGITALTWIN_TEST_RECORD_DIR/opencode-adapter-token\"
else
  printf absent > \"$DIGITALTWIN_TEST_RECORD_DIR/opencode-adapter-token\"
fi
""")
        for command in ["initdb", "pg_ctl", "pg_isready", "psql", "createdb"]:
            self._executable(resources / "postgres" / "bin" / command, "#!/bin/sh\nexit 0\n")
        self._executable(
            resources / "ruby" / "bin" / "ruby",
            "#!/bin/sh\nif test \"${1:-}\" = \"-rsecurerandom\"; then printf fixture-control-token; fi\nexit 0\n",
        )
        for command in ["rake", "falcon"]:
            self._executable(resources / "kirei" / "vendor" / "bundle" / "ruby" / "4.0.0" / "bin" / command, "#!/bin/sh\nexit 0\n")
        (resources / "kirei" / "bin").mkdir(parents=True, exist_ok=True)
        (resources / "kirei" / "bin" / "health").write_text("placeholder")
        (resources / "commander").mkdir(parents=True, exist_ok=True)
        (resources / "commander" / "commander-agent-baseline.md").write_text("# Commander\n")
        (resources / "hermes" / "profile").mkdir(parents=True, exist_ok=True)
        for name in ["config.yaml.example", "SOUL.md", "AGENTS.md"]:
            (resources / "hermes" / "profile" / name).write_text("placeholder\n")
        self._executable(resources / "hermes" / "runtime" / "python" / "bin" / "python3", f"#!/bin/sh\nexec {sys.executable} \"$@\"\n")
        self._executable(resources / "bin" / "hermes", """#!/bin/sh
if test -n \"${ANTHROPIC_API_KEY:-}\"; then
  printf present > \"$DIGITALTWIN_TEST_RECORD_DIR/hermes-anthropic-key\"
else
  printf absent > \"$DIGITALTWIN_TEST_RECORD_DIR/hermes-anthropic-key\"
fi
exec \"$DIGITALTWIN_TEST_PYTHON\" -c '\nimport os\nfrom http.server import BaseHTTPRequestHandler, HTTPServer\nclass Handler(BaseHTTPRequestHandler):\n    def do_GET(self):\n        self.send_response(401)\n        self.end_headers()\n    def log_message(self, *args):\n        return\nHTTPServer(("127.0.0.1", int(os.environ["API_SERVER_PORT"])), Handler).serve_forever()\n'
""")
        self._executable(resources / "bin" / "hermes-adapter", """#!/bin/sh
if test -n \"${ANTHROPIC_API_KEY:-}\"; then
  printf present > \"$DIGITALTWIN_TEST_RECORD_DIR/adapter-anthropic-key\"
else
  printf absent > \"$DIGITALTWIN_TEST_RECORD_DIR/adapter-anthropic-key\"
fi
exec \"$DIGITALTWIN_TEST_PYTHON\" -c '\nimport os\nfrom http.server import BaseHTTPRequestHandler, HTTPServer\nclass Handler(BaseHTTPRequestHandler):\n    def do_GET(self):\n        self.send_response(200)\n        self.end_headers()\n    def log_message(self, *args):\n        return\nHTTPServer(("127.0.0.1", int(os.environ["DIGITALTWIN_HERMES_ADAPTER_PORT"])), Handler).serve_forever()\n'
""")

    def _write_credential(self, data: Path, active: bool) -> None:
        database = data / "opencode" / "data" / "opencode" / "opencode.db"
        database.parent.mkdir(parents=True)
        with sqlite3.connect(database) as connection:
            connection.execute(
                "CREATE TABLE credential (integration_id TEXT, value TEXT, active INTEGER, time_updated INTEGER)"
            )
            connection.execute(
                "INSERT INTO credential VALUES (?, ?, ?, ?)",
                ("anthropic", json.dumps({"type": "key", "key": "fixture-native-anthropic-key"}), int(active), 1),
            )

    def _temporary_root(self):
        WORK_ROOT.mkdir(parents=True, exist_ok=True)
        return tempfile.TemporaryDirectory(dir=WORK_ROOT)

    def _ports(self, count: int) -> list[int]:
        sockets = [socket.socket() for _ in range(count)]
        try:
            for sock in sockets:
                sock.bind(("127.0.0.1", 0))
            return [sock.getsockname()[1] for sock in sockets]
        finally:
            for sock in sockets:
                sock.close()

    def _executable(self, path: Path, source: str) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(source)
        path.chmod(0o755)


if __name__ == "__main__":
    unittest.main()

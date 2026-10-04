"""Real disposable chat/queue/Herdr transports; only the agent is scripted."""
import fnmatch
import json
import os
from pathlib import Path
import secrets
import re
import time
import unittest
import urllib.error
import urllib.request

import test_compose_live as core


@unittest.skipUnless(os.getenv("DIGITALTWIN_RUN_FULL_STACK_TESTS") == "1", "explicit full-stack fixture opt-in required")
class FullStackChatTest(core.DisposableComposeTest):
    sensitive_values = []

    @classmethod
    def redact(cls, value):
        for secret in [*cls.sensitive_values, "local-only-postgres", "local-only-kirei", "local-only-mattermost"]:
            value = value.replace(secret, "<fixture-redacted>")
        return re.sub(r"(postgres(?:ql)?://)[^@\s]+@", r"\1<redacted>@", value)

    @classmethod
    def command(cls, args, **kwargs):
        try:
            result = super().command(args, **kwargs)
        except RuntimeError as error:
            raise RuntimeError(cls.redact(str(error))) from None
        result.stdout = cls.redact(result.stdout)
        result.stderr = cls.redact(result.stderr)
        return result

    def tearDown(self):
        result = self._outcome.result
        failed = any(case.id() == self.id() for case, _ in result.errors + result.failures)
        if failed:
            raw_state = self.compose(["ps", "--all", "--format", "json"], check=False).stdout
            state = [{key: row.get(key) for key in ["Service", "State", "Health", "ExitCode"]}
                     for row in (json.loads(line) for line in raw_state.splitlines())]
            logs = self.compose(["logs", "--no-color", "--tail", "30", "backend-chat-listener", "backend-worker", "backend-web", "agent-runtime"], check=False).stdout
            diagnostic = {"project": self.project, "states": state, "service_logs": logs[-12000:]}
            diagnostic["runtime_boundary_error"] = "\n".join(line for line in self.compose(["logs", "--no-color", "backend-worker"], check=False).stdout.splitlines()
                                                               if "Session runtime effect unproved:" in line or "Fixture Herdr startup failed:" in line or "Fixture Herdr prompt failed:" in line)[-2500:]
            diagnostic["fixture_effects"] = self.effects()
            diagnostic["fixture_errors"] = self.compose(["exec", "-T", "agent-runtime", "python3", "-c",
                                                         "from pathlib import Path; p=Path.home()/'fixture-errors.jsonl'; print(p.read_text() if p.exists() else '')"], check=False).stdout
            diagnostic["raw_start_probe"] = getattr(self, "raw_start_probe", None)
            diagnostic["herdr_panes"] = self.compose(["exec", "-T", "agent-runtime", "herdr", "pane", "list"], check=False).stdout
            diagnostic["job_outcomes"] = self.compose(["exec", "-T", "postgres", "psql", "-U", "postgres", "-d", "digitaltwin_development", "-c",
                                                       "SELECT kind,status,last_error FROM jobs ORDER BY available_at LIMIT 30"], check=False).stdout
            diagnostic["session_operations"] = self.ruby('r=Domains::Sessions::Registry.new; sessions=r.all_active+r.pending_starts(workflow_id:nil,role:Domains::Sessions::Dto::SessionRole::Commander); puts JSON.generate(sessions.map{|s| o=Domains::Sessions::Operations.new.for_session(session_id:s.id,kind:Domains::Sessions::Dto::OperationKind::Start); {id:s.id,pane:s.pane_id,active:s.active,state:s.state.serialize,operation_state:o&.state&.serialize,operation_reason:o&.reason}})', check=False).stdout
            sanitized = self.redact(json.dumps(diagnostic))
            print("Disposable full-stack failure: " + sanitized)
            artifact = os.environ.get("DIGITALTWIN_TEST_ARTIFACTS")
            if artifact:
                directory = Path(artifact)
                directory.mkdir(parents=True, exist_ok=True)
                (directory / "full-stack-failure.json").write_text(sanitized + "\n")

    def request(self, method, path, body=None, token=None, expected=200):
        headers = {"Content-Type": "application/json"}
        if token:
            headers["Authorization"] = "Bearer " + token
        request = urllib.request.Request(self.addresses["mattermost"] + "/api/v4" + path,
                                         data=None if body is None else json.dumps(body).encode(), headers=headers, method=method)
        try:
            response = urllib.request.urlopen(request, timeout=15)
        except urllib.error.HTTPError as error:
            if error.code == expected:
                return {}, error.headers
            raise AssertionError(f"Mattermost {method} {path} returned {error.code}, expected {expected}") from None
        with response:
            self.assertEqual(response.status, expected)
            value = json.load(response)
            # Login/session and bot token values stay only in memory and owned volumes.
            session = response.headers.get("Token")
            if session:
                self.sensitive_values.append(session)
            if isinstance(value, dict) and "token" in value:
                self.sensitive_values.append(value["token"])
            return value, response.headers

    def poll(self, predicate, message, timeout=60):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            value = predicate()
            if value:
                return value
            time.sleep(0.25)
        self.fail(message)

    def create_user(self, name):
        password = secrets.token_urlsafe(24)
        self.sensitive_values.append(password)
        user, _ = self.request("POST", "/users", {"username": name, "email": name + "@fixture.invalid", "password": password}, token=getattr(self, "admin_token", None), expected=201)
        _, headers = self.request("POST", "/users/login", {"login_id": name, "password": password})
        return user, headers["Token"]

    def configure_chat(self):
        fixture = core.ROOT / "tests/fixtures/full_stack"
        self.auth_volume = self.project + "_e2e-auth"
        environment = {
            "MATTERMOST_URL": "http://mattermost:8065",
            "MATTERMOST_LISTENER_TOKEN_FILE": "/auth/listener.token",
            "MATTERMOST_AGENT_TOKEN_FILE": "/auth/agent.token",
            "MATTERMOST_WORKER_TOKEN_FILE": "/auth/worker.token",
            "ROLE_CONFIG_FILE": "/auth/roles.json",
        }
        override = {
            "services": {
                "mattermost": {"environment": {"MM_SERVICESETTINGS_ENABLEBOTACCOUNTCREATION": "true", "MM_SERVICESETTINGS_ENABLEUSERACCESSTOKENS": "true", "MM_TEAMSETTINGS_ENABLEJOINLEAVEMESSAGE": "false"}},
                "fixture-auth-init": {"image": "busybox:1.37", "platform": "linux/amd64", "user": "0:0", "network_mode": "none",
                                      "volumes": ["e2e-auth:/auth"], "command": ["sh", "-c", "chown 10001:10001 /auth; chmod 700 /auth"]},
                "backend-web": {"environment": environment, "volumes": ["e2e-auth:/auth:ro", str(fixture) + ":/app/e2e_fixtures:ro"]},
                "backend-worker": {"environment": {**environment, "RACK_ENV": "test", "CHAT_VALIDATION_MODE": "1", "DIGITALTWIN_DISPOSABLE_TEST_PROJECT": self.project},
                                   "volumes": ["e2e-auth:/auth", str(fixture) + ":/e2e:ro"], "command": ["bundle", "exec", "ruby", "/e2e/worker.rb"]},
                "backend-chat-listener": {"image": self.project + "-backend:check", "environment": environment, "volumes": ["e2e-auth:/auth:ro"]},
                "agent-runtime": {"volumes": [str(fixture / "pi") + ":/usr/local/bin/pi:ro"]},
            },
            "volumes": {"e2e-auth": {}},
        }
        path = Path(self.temporary.name) / "full-stack.json"
        path.write_text(json.dumps(override))
        type(self).base += ["-f", str(path)]
        self.compose(["run", "--rm", "--no-deps", "fixture-auth-init"])
        self.compose(["up", "-d", "--no-build", "--wait", "--wait-timeout", "120", "mattermost", "agent-runtime"], timeout=180)
        self.refresh_addresses()
        self.admin, self.admin_token = self.create_user("fixture-admin")
        self.assertIn("system_admin", self.admin["roles"].split())
        self.human, self.human_token = self.create_user("fixture-human")
        self.outsider, self.outsider_token = self.create_user("fixture-outsider")
        bots = {}
        tokens = {"listener": self.admin_token}
        for role in ["agent", "worker"]:
            bot, _ = self.request("POST", "/bots", {"username": role, "display_name": "Commander Shepard" if role == "agent" else "Fixture Worker"}, self.admin_token, 201)
            bots[role] = bot["user_id"]
            credential, _ = self.request("POST", "/users/" + bot["user_id"] + "/tokens", {"description": "Disposable integration fixture"}, self.admin_token, 200)
            tokens[role] = credential["token"]
        team, _ = self.request("POST", "/teams", {"name": "fixture-team", "display_name": "Disposable fixture", "type": "I"}, self.admin_token, 201)
        members = [self.admin["id"], self.human["id"], *bots.values()]
        for user in members:
            self.request("POST", "/teams/" + team["id"] + "/members", {"team_id": team["id"], "user_id": user}, self.admin_token, 201)
        self.channels = []
        for name in ["fixture-one", "fixture-two"]:
            channel, _ = self.request("POST", "/channels", {"team_id": team["id"], "name": name, "display_name": name, "type": "P"}, self.admin_token, 201)
            self.channels.append(channel["id"])
            for user in members[1:]:
                self.request("POST", "/channels/" + channel["id"] + "/members", {"user_id": user}, self.admin_token, 201)
        # Clear only setup-generated posts in fresh fixture channels before listening.
        for channel in self.channels:
            initial, _ = self.request("GET", "/channels/" + channel + "/posts", token=self.admin_token)
            for post in initial["posts"].values():
                self.request("DELETE", "/posts/" + post["id"], token=self.admin_token)
        environment.update({"MATTERMOST_LOCAL_BOT_IDS": ",".join(bots.values()), "MATTERMOST_CHANNEL_IDS": ",".join(self.channels),
                            "COMMANDER_CHANNEL_ID": self.channels[0], "MATTERMOST_AGENT_BOT_ID": bots["agent"], "MATTERMOST_WORKER_BOT_ID": bots["worker"]})
        for service in ["backend-web", "backend-worker", "backend-chat-listener"]:
            override["services"][service]["environment"].update(environment)
        path.write_text(json.dumps(override))
        role = {"cli": "pi", "provider": "fixture", "model": "deterministic", "family": "fixture", "launch_args": []}
        files = {**{name + ".token": value for name, value in tokens.items()}, "roles.json": json.dumps({"commander": role}), "ready": self.project}
        # Ruby has no app bootstrap here: write secret values from stdin, never argv/env/logs.
        self.compose(["run", "--rm", "--no-deps", "-T", "--entrypoint", "ruby", "backend-worker", "-rjson", "-e",
                      "JSON.parse(STDIN.read).each{|name,value| File.write('/auth/'+name,value,mode:'w',perm:0600)}"], source=json.dumps(files))
        self.base[2:2] = ["--profile", "chat-validation"]
        self.compose(["up", "-d", "--no-build", "--wait", "--wait-timeout", "120", "backend-web", "backend-worker", "backend-chat-listener"], timeout=180)
        self.refresh_addresses()
        self.agent_id = bots["agent"]
        self.agent_token = tokens["agent"]

    def effects(self):
        result = self.compose(["exec", "-T", "agent-runtime", "python3", "-c",
                               "from pathlib import Path; p=Path.home()/'fixture-effects.jsonl'; print(p.read_text() if p.exists() else '')"])
        return [json.loads(row) for row in result.stdout.splitlines() if row.strip()]

    def reply_for(self, nonce, channel):
        data, _ = self.request("GET", "/channels/" + channel + "/posts", token=self.human_token)
        return [post for post in data["posts"].values() if post["message"] == "E2E_REPLY=" + nonce]

    def test_backend_checks(self):
        for database in ["digitaltwin_backend_test", "digitaltwin_migration_test"]:
            self.compose(["exec", "-T", "postgres", "createdb", "-U", "postgres", database])
        result = self.compose(["run", "--rm", "--no-deps", "-T",
                               "-e", "DATABASE_URL=postgres://postgres:local-only-postgres@postgres:5432/digitaltwin_backend_test",
                               "-e", "MIGRATION_TEST_DATABASE_URL=postgres://postgres:local-only-postgres@postgres:5432/digitaltwin_migration_test",
                               "backend-web", "env", "-u", "ROLE_CONFIG_FILE", "bin/check"], timeout=600, check=False)
        self.assertEqual(result.returncode, 0, "Full backend checks failed:\n" + result.stdout[-2500:] + result.stderr[-2500:])
        self.assertIn("No errors", result.stdout + result.stderr)
        self.assertIn("no offenses detected", result.stdout)
        self.evidence["full_backend_tests_rubocop_sorbet_with_fixture_classes"] = True
        counts = re.findall(r"(\d+) examples?, (\d+) failures?", result.stdout)
        self.assertEqual(len(counts), 3, "all backend subprocess totals required")
        self.evidence["backend_examples"] = sum(int(examples) for examples, _ in counts)
        self.evidence["backend_failures"] = sum(int(failures) for _, failures in counts)

    def test_real_chat_and_herdr_roundtrip(self):
        self.configure_chat()
        self.ruby("abort 'production gate opened' if Domains::Workflows::Policy.new.dispatch_allowed?")
        checkpoint_json = self.ruby("c=Domains::Messaging::Checkpoints.new; puts JSON.generate(" + json.dumps(self.channels) + ".to_h{|id| [id,c.revision(channel_id:id)]})").stdout.splitlines()[-1]
        checkpoints_before = json.loads(checkpoint_json)
        # The CLI waits after raw agent.start; record its distinct socket semantics.
        probe = r"""
import json, socket, time, uuid
from pathlib import Path

def call(method, params):
    with socket.socket(socket.AF_UNIX) as client:
        client.connect('/run/herdr/herdr.sock')
        stream = client.makefile('rwb')
        stream.write((json.dumps({'id': uuid.uuid4().hex, 'method': method, 'params': params})+'\n').encode())
        stream.flush()
        return json.loads(stream.readline())

observations = []
for delay, name in [(0, 'wire-probe'), (0.5, 'wire-probe'), (0, 'digitaltwin-session_abCDEF123xyz')]:
    created = call('workspace.create', {'cwd': '/home/runtime', 'label': 'wire-probe', 'env': {}, 'focus': False})['result']
    try:
        time.sleep(delay)
        started = call('agent.start', {'pane_id': created['root_pane']['pane_id'], 'name': name, 'kind': 'pi', 'args': []})
        agent = started.get('result', {}).get('agent', {})
        observations.append({'delay': delay, 'name': name, 'error_code': started.get('error', {}).get('code'),
                             'result_type': started.get('result', {}).get('type'),
                             'state': agent.get('agent_status'), 'launch_pending': agent.get('launch_pending'),
                             'interactive_ready': agent.get('interactive_ready'), 'has_session': bool(agent.get('agent_session'))})
    finally:
        call('workspace.close', {'workspace_id': created['workspace']['workspace_id']})
print(json.dumps(observations))
"""
        self.raw_start_probe = json.loads(self.compose(["exec", "-T", "agent-runtime", "python3", "-c", probe]).stdout)
        created = json.loads(self.compose(["exec", "-T", "agent-runtime", "herdr", "workspace", "create", "--label", "direct-fixture", "--cwd", "/home/runtime"]).stdout)["result"]
        pane = created["root_pane"]["pane_id"]
        try:
            self.compose(["exec", "-T", "agent-runtime", "herdr", "agent", "start", "direct-fixture", "--kind", "pi", "--pane", pane, "--timeout", "8000"])
            self.compose(["exec", "-T", "agent-runtime", "herdr", "agent", "prompt", pane, "DIRECT_MESSAGE=direct", "--wait"])
            direct = self.poll(lambda: [row for row in self.effects() if row["nonce"] == "direct"], "direct Herdr fixture did not receive prompt")
            self.assertEqual(len(direct), 1)
            live = json.loads(self.compose(["exec", "-T", "agent-runtime", "herdr", "agent", "get", pane]).stdout)["result"]["agent"]
            self.assertEqual(live["agent_session"]["value"], direct[0]["session_id"])
            screen = self.compose(["exec", "-T", "agent-runtime", "herdr", "pane", "read", pane]).stdout
            self.assertIn("DIRECT_REPLY=direct", screen)
        finally:
            self.compose(["exec", "-T", "agent-runtime", "herdr", "workspace", "close", created["workspace"]["workspace_id"]])
        self.request("POST", "/posts", {"channel_id": self.channels[0], "message": "E2E_MESSAGE=forbidden"}, self.outsider_token, 403)
        roots = []
        for index, channel in enumerate(self.channels):
            root, _ = self.request("POST", "/posts", {"channel_id": channel, "message": "@agent E2E_MESSAGE=bot-forbidden"}, self.agent_token, 201)
            roots.append(root["id"])
        posts = []
        for index, channel in enumerate(self.channels):
            post, _ = self.request("POST", "/posts", {"channel_id": channel, "root_id": roots[index], "message": "@agent E2E_MESSAGE=chat-" + str(index)}, self.human_token, 201)
            posts.append(post["id"])
        for index, channel in enumerate(self.channels):
            replies = self.poll(lambda: self.reply_for("chat-" + str(index), channel), "chat reply did not reach real Mattermost")
            self.assertEqual(len(replies), 1)
            self.assertEqual((replies[0]["root_id"], replies[0]["user_id"]), (roots[index], self.agent_id))
            self.assertFalse(self.reply_for("chat-" + str(index), self.channels[1 - index]))
        before = self.poll(lambda: [row for row in self.effects() if row["request_id"]], "chat prompts did not reach agent")
        self.assertEqual({row["nonce"] for row in before}, {"chat-0", "chat-1"})
        self.assertEqual(len(before), 2)
        self.assertTrue(all(row["mcp"] for row in before))
        self.evidence["identical_replay_attempts"] = [row["replay_attempts"] for row in before]
        self.assertEqual(len({(row["session_id"], row["pane_id"]) for row in before}), 1)
        # WS delivery must be observed before reconnect/backfill can hide a broken WS parser.
        self.ruby("checkpoints=Domains::Messaging::Checkpoints.new; abort 'live WS absent' unless " +
                  " && ".join(f"checkpoints.revision(channel_id:'{channel}') == {checkpoints_before[channel]}" for channel in self.channels))
        self.compose(["restart", "backend-chat-listener", "backend-worker", "backend-web"])
        self.compose(["up", "-d", "--no-build", "--wait", "--wait-timeout", "120", "backend-web", "backend-worker", "backend-chat-listener"], timeout=180)
        self.refresh_addresses()
        self.poll(lambda: self.ruby("c=Domains::Messaging::Checkpoints.new; abort unless " +
                                   " && ".join(f"c.revision(channel_id:'{channel}') > 0" for channel in self.channels), check=False).returncode == 0,
                  "real REST backfill did not replay history")
        self.assertEqual([row for row in self.effects() if row["request_id"]], before)
        for index, channel in enumerate(self.channels):
            self.assertEqual(len(self.reply_for("chat-" + str(index), channel)), 1)
        followup, _ = self.request("POST", "/posts", {"channel_id": self.channels[0], "root_id": roots[0], "message": "@agent E2E_MESSAGE=after-restart"}, self.human_token, 201)
        self.poll(lambda: self.reply_for("after-restart", self.channels[0]), "restart lost chat routing")
        after = self.poll(lambda: [row for row in self.effects() if row["nonce"] == "after-restart"], "restart prompt did not reach existing agent")
        self.assertEqual(len(after), 1)
        self.assertEqual((after[0]["session_id"], after[0]["pane_id"]), (before[0]["session_id"], before[0]["pane_id"]))
        self.assertFalse(any(row["nonce"] in {"forbidden", "bot-forbidden"} for row in self.effects()))
        self.evidence.update({"authenticated_disposable_chat": True, "real_chat_rest_and_websocket": True,
                              "real_herdr_fixture_agent": True, "real_backend_mcp_http_with_fixture_agent": True,
                              "fixture_agent_only": True, "correct_threads_and_bot": True, "duplicate_one_effect": True,
                              "backend_restart_same_conversation": True, "production_dispatch_policy": False})


def load_tests(loader, tests, pattern):
    # Reuse Compose lifecycle; the six base checks run once in their original module.
    cases = [FullStackChatTest("test_real_chat_and_herdr_roundtrip"), FullStackChatTest("test_backend_checks")]
    return unittest.TestSuite(case for case in cases if not loader.testNamePatterns or
                              any(fnmatch.fnmatchcase(case.id(), pattern) for pattern in loader.testNamePatterns))

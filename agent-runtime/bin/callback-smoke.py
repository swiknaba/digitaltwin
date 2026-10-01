#!/usr/bin/env python3
"""Package check against a disposable HTTP fixture, not Kirei integration."""
import http.server
import json
import os
from pathlib import Path
import subprocess
import tempfile
import threading

received = []
code = 202
class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        received.append((self.path, self.headers.get('Authorization'), json.loads(self.rfile.read(int(self.headers['Content-Length'])))))
        self.send_response(code)
        self.end_headers()
        self.wfile.write(b'Fixture body must not be logged')
    def log_message(self, *args):
        pass

with tempfile.TemporaryDirectory(prefix='callback-package-') as scratch:
    token = Path(scratch, 'fixture-token')
    token.write_text('public-disposable-fixture-value\n')
    token.chmod(0o600)
    with http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler) as server:
        thread = threading.Thread(target=server.serve_forever)
        thread.start()
        env = dict(os.environ, DIGITALTWIN_SESSION_TOKEN_FILE=str(token), DIGITALTWIN_SESSION_GENERATION='7', DIGITALTWIN_CALLBACK_URL=f'http://127.0.0.1:{server.server_port}')
        try:
            for response_code in (202, 403):
                code = response_code
                result = subprocess.run(['digitaltwin', 'say', '--text', 'fixture question', '--key', 'fixture:one'], env=env, capture_output=True, text=True, timeout=20)
                assert result.returncode == (0 if code == 202 else 1), result.stderr
                assert 'public-disposable-fixture-value' not in result.stdout + result.stderr
                assert 'Fixture body' not in result.stdout + result.stderr
            assert len(received) == 2  # no automatic retry
            for path, authorization, payload in received:
                assert path == '/internal/callbacks/say'
                assert authorization == 'Bearer public-disposable-fixture-value'
                assert payload == {'generation': 7, 'key': 'fixture:one', 'text': 'fixture question'}
            result = subprocess.run(['digitaltwin', 'artifact-ready'], env=env, capture_output=True, text=True)
            assert result.returncode == 1
            assert len(received) == 2
        finally:
            server.shutdown()
            thread.join()
print('PASS: backend-owned packaged client, exact callback fields/path/header, accepted/rejected responses, no retry or credential/body output; HTTP fixture only')

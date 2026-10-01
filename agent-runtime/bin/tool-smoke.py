#!/usr/bin/env python3
"""Functional tool fixtures; never starts an LLM or touches project files."""
import csv
import hashlib
import http.server
import json
import os
from pathlib import Path
import subprocess
import tempfile
import threading


def run(*args, expected=0, **kwargs):
    result = subprocess.run(args, capture_output=True, text=True, **kwargs)
    assert result.returncode == expected, (args, result.returncode, result.stderr)
    return result.stdout


with tempfile.TemporaryDirectory(prefix='runtime-smoke-') as scratch:
    root = Path(scratch)
    fixture = root / 'space file.txt'
    fixture.write_text('needle\nbeta\nbeta\n')
    (root / '.hidden').write_text('needle\n')
    (root / '.gitignore').write_text('ignored.txt\n')
    (root / 'ignored.txt').write_text('needle\n')
    run('git', 'init', '-q', str(root))
    assert '.hidden' not in run('rg', '-l', 'needle', str(root))
    assert '.hidden' in run('rg', '--hidden', '--glob', '!.git/**', '-l', 'needle', str(root))
    assert 'ignored.txt' in run('rg', '--hidden', '--no-ignore', '-l', 'needle', str(root))
    assert 'space file.txt' in run('fd', '--type', 'f', 'space', str(root))
    assert '.hidden' in run('fd', '--hidden', '--no-ignore', '--type', 'f', 'hidden', str(root))
    assert run('grep', '-o', 'needle', str(fixture)).strip() == 'needle'
    run('grep', 'absent', str(fixture), expected=1)
    assert run('sed', 's/needle/replaced/', str(fixture)).startswith('replaced\n')
    assert run('bash', '-c', 'sort "$1" | uniq', 'smoke', str(fixture)) == 'beta\nneedle\n'
    assert run('sh', '-c', "printf 'a b\\n' | awk '{print $2}'") == 'b\n'
    assert run('bash', '-c', 'find "$1" -maxdepth 1 -type f -print0 | xargs -0 -r printf "%s\\n"', 'smoke', scratch).count('space file.txt') == 1
    assert int(run('stat', '-c', '%s', str(fixture))) == fixture.stat().st_size
    assert run('realpath', str(fixture)).strip() == str(fixture)
    assert run('sha256sum', str(fixture)).split()[0] == hashlib.sha256(fixture.read_bytes()).hexdigest()
    run('timeout', '0.1', 'sh', '-c', 'sleep 2', expected=124)
    data = {'answer': 42}
    source = root / 'data.json'
    source.write_text(json.dumps(data))
    assert run('jq', '-e', '.answer == 42', str(source)).strip() == 'true'
    table = root / 'data.csv'
    with table.open('w') as stream:
        csv.writer(stream).writerows([['value'], ['42']])
    with table.open() as stream:
        assert list(csv.DictReader(stream)) == [{'value': '42'}]
    run('git', '-C', scratch, 'config', 'user.email', 'fixture@example.invalid')
    run('git', '-C', scratch, 'config', 'user.name', 'Runtime fixture')
    run('git', '-C', scratch, 'add', 'space file.txt')
    run('git', '-C', scratch, 'commit', '-qm', 'fixture')
    worktree = root / 'worktree'
    run('git', '-C', scratch, 'worktree', 'add', '-qb', 'smoke', str(worktree))
    fixture.write_text('changed\nbeta\nbeta\n')
    patch = root / 'edit.patch'
    patch.write_text(run('git', '-C', scratch, 'diff'))
    run('patch', '-d', str(worktree), '-p1', '-i', str(patch))
    assert (worktree / fixture.name).read_bytes() == fixture.read_bytes()
    assert 'text' in run('file', str(fixture)).lower()
    run('tar', '-czf', str(root / 'fixture.tar.gz'), '-C', scratch, fixture.name)
    run('gzip', '-t', str(root / 'fixture.tar.gz'))
    extracted = root / 'extracted'
    extracted.mkdir()
    run('tar', '-xzf', str(root / 'fixture.tar.gz'), '-C', str(extracted))
    run('cmp', str(fixture), str(extracted / fixture.name))
    run('zip', '-q', str(root / 'fixture.zip'), fixture.name, cwd=scratch)
    run('unzip', '-oq', str(root / 'fixture.zip'), '-d', str(extracted))
    run('cmp', str(fixture), str(extracted / fixture.name))
    class Handler(http.server.SimpleHTTPRequestHandler):
        def __init__(self, *args, **kwargs):
            super().__init__(*args, directory=scratch, **kwargs)
        def log_message(self, *args):
            pass
    with http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler) as server:
        thread = threading.Thread(target=server.serve_forever)
        thread.start()
        try:
            url = f'http://127.0.0.1:{server.server_port}'
            assert json.loads(run('curl', '--fail', '--silent', url + '/data.json')) == data
            run('curl', '--fail', '--silent', url + '/missing', expected=22)
        finally:
            server.shutdown()
            thread.join()
    assert Path('/etc/ssl/certs/ca-certificates.crt').stat().st_size > 0
    assert 'https' in run('curl', '--version')
    assert not list(root.rglob('__pycache__'))
assert not root.exists()
try:
    with tempfile.TemporaryDirectory(prefix='runtime-failure-') as failure:
        raise RuntimeError('expected fixture failure')
except RuntimeError:
    assert not Path(failure).exists()
print('PASS: search/ignore/spaces, GNU text/files, Git/worktree/patch, JSON/CSV/hash, HTTP errors, archives, cleanup')

#!/usr/bin/env python3
"""Unauthenticated startup observations; never counts as live LLM acceptance.

Run inside a disposable Runtime server with empty home and no provider secrets.
Outputs only local startup state/screens. Do not use against an operator home.
"""
import json
import subprocess
import time


def call(*args):
    result = subprocess.run(['herdr', *args], text=True, capture_output=True, timeout=20)
    return result


for kind in ('codex', 'claude', 'opencode', 'gemini'):
    created = call('workspace', 'create', '--label', 'unauthenticated-' + kind, '--cwd', '/home/runtime')
    workspace = json.loads(created.stdout)['result']
    pane = workspace['root_pane']['pane_id']
    time.sleep(1)
    startup = call('agent', 'start', 'offline-' + kind, '--kind', kind, '--pane', pane, '--timeout', '8000')
    screen = call('pane', 'read', pane)
    state = call('pane', 'get', pane)
    print(json.dumps({'cli': kind, 'startup_exit': startup.returncode, 'startup_response': startup.stdout or startup.stderr, 'pane_state': state.stdout, 'screen': screen.stdout, 'authenticated': False}), flush=True)
    call('workspace', 'close', workspace['workspace']['workspace_id'])

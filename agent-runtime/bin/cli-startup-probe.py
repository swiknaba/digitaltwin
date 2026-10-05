#!/usr/bin/env python3
"""Unauthenticated startup observations; never counts as live LLM acceptance.

Run inside a disposable Runtime server with empty home and no provider secrets.
Outputs only local startup state/screens. Do not use against an operator home.
"""
import json
import os
import subprocess
import time


def call(*args):
    result = subprocess.run(['herdr', *args], text=True, capture_output=True, timeout=20)
    return result


# Hermes remains the Commander harness. Grok Build is a separate xAI worker
# CLI which Herdr supports natively as ``grok``; it is not Hermes' xAI
# provider selection. This probe submits no prompt and has no credentials.
supported_kinds = ('codex', 'claude', 'opencode', 'gemini', 'hermes', 'grok')
requested_kinds = os.environ.get('CLI_STARTUP_PROBE_KINDS')
kinds = tuple(requested_kinds.split(',')) if requested_kinds else supported_kinds
if not kinds or any(kind not in supported_kinds for kind in kinds):
    raise SystemExit('CLI_STARTUP_PROBE_KINDS must be a non-empty comma-separated subset of supported CLI kinds')

for kind in kinds:
    created = call('workspace', 'create', '--label', 'unauthenticated-' + kind, '--cwd', '/home/runtime')
    workspace = json.loads(created.stdout)['result']
    pane = workspace['root_pane']['pane_id']
    time.sleep(1)
    startup = call('agent', 'start', 'offline-' + kind, '--kind', kind, '--pane', pane, '--timeout', '8000')
    screen = call('pane', 'read', pane)
    state = call('pane', 'get', pane)
    print(json.dumps({'cli': kind, 'startup_exit': startup.returncode, 'startup_response': startup.stdout or startup.stderr, 'pane_state': state.stdout, 'screen': screen.stdout, 'authenticated': False}), flush=True)
    call('workspace', 'close', workspace['workspace']['workspace_id'])

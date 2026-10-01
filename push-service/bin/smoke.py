#!/usr/bin/env python3
"""Probe only a disposable provider-free container using its existing netcat."""
import argparse
import json
import subprocess


def request(container, method, path, body=b''):
    wire = (f'{method} {path} HTTP/1.0\r\nHost: localhost\r\nContent-Type: application/json\r\nContent-Length: {len(body)}\r\n\r\n').encode() + body
    result = subprocess.run(['docker', 'exec', '-i', container, 'nc', '-w', '2', '127.0.0.1', '8066'], input=wire, capture_output=True, check=True, timeout=10)
    headers, content = result.stdout.split(b'\r\n\r\n', 1)
    return int(headers.split(b' ', 2)[1]), content


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('container', help='disposable container with empty provider settings only')
    args = parser.parse_args()
    cfg = subprocess.run(['docker', 'exec', args.container, 'cat', '/mattermost-push-proxy/config/mattermost-push-proxy.json'], capture_output=True, check=True, timeout=10)
    cfg = json.loads(cfg.stdout)
    if cfg.get('ApplePushSettings') != [] or cfg.get('AndroidPushSettings') != []:
        parser.error('smoke requires empty provider arrays to prevent external delivery')
    code, body = request(args.container, 'GET', '/version')
    version = json.loads(body)
    assert code == 200 and version['version'] == '6.6.0' and version['hash'].startswith('20f2a04'), (code, version)
    code, body = request(args.container, 'GET', '/')
    assert code == 200 and b'Mattermost Push Proxy' in body
    cases = [
        (b'{', 'Failed to read message body'),
        (b'{}', 'missing server Id'),
        (b'{"server_id":"fixture"}', 'missing device Id'),
        (b'{"server_id":"fixture","device_id":"fixture","platform":"apple_rn-v2"}', 'type=apple_rn'),
        (b'{"server_id":"fixture","device_id":"fixture","platform":"android_rn-v2"}', 'type=android_rn'),
    ]
    for payload, expected in cases:
        for _ in range(2):  # Repeat safe failures: never treat HTTP 200 as delivered.
            code, body = request(args.container, 'POST', '/api/v1/send_push', payload)
            response = json.loads(body)
            assert code == 200 and response['status'] == 'FAIL' and expected in response['error'], (code, response)
    assert request(args.container, 'GET', '/api/v1/send_push')[0] == 404
    print('PASS: pinned version, process health, 10 repeated error responses, React Native platform parsing, method rejection; no provider delivery')

if __name__ == '__main__': main()

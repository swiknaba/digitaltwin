#!/usr/bin/env python3
"""Non-secret preflight for our upstream 6.6.0 configuration recipe."""
import argparse
import json
from pathlib import PurePosixPath
import sys

TOP = {'ListenAddress', 'ThrottlePerSec', 'ThrottleMemoryStoreSize', 'ThrottleVaryByHeader', 'EnableMetrics', 'SendTimeoutSec', 'RetryTimeoutSec', 'ApplePushSettings', 'AndroidPushSettings', 'EnableConsoleLog', 'EnableFileLog', 'LogFileLocation', 'LogFormat', 'LogLevel'}
APPLE = {'Type', 'ApplePushUseDevelopment', 'ApplePushCertPrivate', 'ApplePushCertPassword', 'ApplePushTopic', 'AppleAuthKeyFile', 'AppleAuthKeyID', 'AppleTeamID'}
ANDROID = {'Type', 'ServiceFileLocation'}


def require(ok, message):
    if not ok:
        raise ValueError(message)


def secret_path(value):
    require(isinstance(value, str) and value.startswith('/run/secrets/') and '..' not in PurePosixPath(value).parts and len(PurePosixPath(value).parts) > 3, 'credential must be a mounted file under /run/secrets')


def validate(cfg, delivery=False):
    require(isinstance(cfg, dict) and not (cfg.keys() - TOP), 'unknown top-level configuration field')
    require(cfg.get('ListenAddress') == ':8066', 'recipe requires ListenAddress :8066')
    for key in ['SendTimeoutSec', 'RetryTimeoutSec', 'ThrottlePerSec', 'ThrottleMemoryStoreSize']:
        require(type(cfg.get(key)) is int and cfg[key] > 0, 'positive integer required for ' + key)
    require(cfg['RetryTimeoutSec'] <= cfg['SendTimeoutSec'], 'retry timeout exceeds total send timeout')
    require(cfg.get('EnableConsoleLog') is True and cfg.get('EnableFileLog') is False, 'recipe requires console logging only')
    require(cfg.get('LogLevel') in {'info', 'warn', 'error'} and cfg.get('LogFormat') == 'json', 'recipe requires JSON logs without debug payload logging')
    require(type(cfg.get('EnableMetrics')) is bool, 'EnableMetrics must be boolean')
    require(cfg.get('ThrottleVaryByHeader') == '', 'private recipe does not trust forwarded headers')
    all_types = set()
    for field, fields, target in [('ApplePushSettings', APPLE, 'apple_rn'), ('AndroidPushSettings', ANDROID, 'android_rn')]:
        settings = cfg.get(field)
        require(isinstance(settings, list), 'target settings must be arrays')
        if delivery: require(len(settings) == 1, 'delivery recipe requires one React Native target per platform')
        for item in settings:
            require(isinstance(item, dict) and not (item.keys() - fields), 'unknown target configuration field')
            require(item.get('Type') == target and target not in all_types, 'unexpected or duplicate platform target')
            all_types.add(target)
            if target == 'apple_rn':
                require(item.get('ApplePushCertPrivate', '') == '' and item.get('ApplePushCertPassword', '') == '', 'recipe uses APNs key files; inline certificate passwords are prohibited')
                secret_path(item.get('AppleAuthKeyFile'))
                require(all(isinstance(item.get(k), str) and item[k].strip() and not item[k].startswith('op://') for k in ['AppleAuthKeyID', 'AppleTeamID', 'ApplePushTopic']), 'APNs key ID, team ID and topic required')
                require(type(item.get('ApplePushUseDevelopment')) is bool, 'APNs environment must be boolean')
            else:
                secret_path(item.get('ServiceFileLocation'))
    return cfg


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('config')
    parser.add_argument('--delivery', action='store_true', help='require both provider target definitions; does not prove provider readiness')
    args = parser.parse_args()
    try:
        with open(args.config) as stream: cfg = json.load(stream)
        validate(cfg, args.delivery)
    except (OSError, ValueError, TypeError):
        # Upstream prints malformed JSON: reject safely before starting it.
        print('configuration rejected; check fields, timeouts, target identities and mounted file references', file=sys.stderr)
        return 1
    print('configuration preflight passed; provider readiness remains unverified')
    return 0

if __name__ == '__main__': sys.exit(main())

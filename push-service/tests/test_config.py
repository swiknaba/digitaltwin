import copy
import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]

class ConfigChecks(unittest.TestCase):
    def setUp(self):
        spec = importlib.util.spec_from_file_location('config_check', ROOT / 'bin/check-config.py')
        self.check = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.check)
        self.local = json.loads((ROOT / 'config/local.json').read_text())
        self.delivery = json.loads((ROOT / 'config/delivery.example.json').read_text())

    def test_preflight_distinguishes_process_only_from_delivery(self):
        self.check.validate(self.local)
        with self.assertRaises(ValueError): self.check.validate(self.local, delivery=True)
        self.check.validate(self.delivery, delivery=True)

    def test_rejects_unknown_fields_and_unsafe_timeouts(self):
        for key, value in [('APNSKey', 'typo'), ('SendTimeoutSec', 0), ('RetryTimeoutSec', 31)]:
            cfg = copy.deepcopy(self.local)
            cfg[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError): self.check.validate(cfg)

    def test_rejects_inline_secrets_and_unresolved_references(self):
        for key, value in [('ApplePushCertPassword', 'sensitive'), ('AppleAuthKeyFile', 'op://vault/item/key'), ('AppleAuthKeyFile', '/run/secrets/../key')]:
            cfg = copy.deepcopy(self.delivery)
            cfg['ApplePushSettings'][0][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError): self.check.validate(cfg, delivery=True)

    def test_rejects_missing_or_duplicate_target_configuration(self):
        for mutate in [lambda c: c['ApplePushSettings'][0].pop('AppleTeamID'), lambda c: c['AndroidPushSettings'].append(c['AndroidPushSettings'][0])]:
            cfg = copy.deepcopy(self.delivery)
            mutate(cfg)
            with self.assertRaises(ValueError): self.check.validate(cfg, delivery=True)

if __name__ == '__main__': unittest.main()

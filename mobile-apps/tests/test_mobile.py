import importlib.util
import json
import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]

class MobileTests(unittest.TestCase):
    def run_tool(self, *args):
        return subprocess.run(['python3', str(ROOT / 'bin/mobile'), *map(str, args)], text=True, capture_output=True)

    def test_wrong_revision_is_rejected_without_changes(self):
        with tempfile.TemporaryDirectory() as d:
            p = pathlib.Path(d)
            subprocess.run(['git', 'init', '-q', str(p)], check=True)
            (p / 'file').write_text('fixture')
            subprocess.run(['git', '-C', d, 'add', '.'], check=True)
            subprocess.run(['git', '-C', d, '-c', 'commit.gpgsign=false', '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-qm', 'fixture'], check=True)
            before = (p / 'file').read_bytes()
            result = self.run_tool('verify', '--source', p)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('revision', result.stderr)
            self.assertEqual(before, (p / 'file').read_bytes())

    def test_configuration_rejects_secrets_and_upstream_identity(self):
        with tempfile.TemporaryDirectory() as d:
            config = pathlib.Path(d) / 'config.json'
            for value in [
                {'app_id': 'com.mattermost.rnbeta', 'server_url': 'https://chat.example.invalid', 'name': 'Digitaltwin'},
                {'app_id': 'org.example.digitaltwin', 'server_url': 'https://user:password@chat.example.invalid', 'name': 'Digitaltwin'},
                {'app_id': 'org.example.digitaltwin', 'server_url': 'https://chat.example.invalid', 'name': 'Digitaltwin', 'signing_key': 'secret'},
            ]:
                config.write_text(json.dumps(value))
                result = self.run_tool('check-config', '--config', config)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('configuration', result.stderr)

    def test_configuration_accepts_non_secret_operator_inputs(self):
        result = self.run_tool('check-config', '--config', ROOT / 'config/app.example.json')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_unsigned_build_command_has_no_signing_or_publication(self):
        for platform in ['android', 'ios']:
            result = self.run_tool('commands', platform)
            self.assertEqual(result.returncode, 0, result.stderr)
            commands = json.loads(result.stdout)
            flat = str(commands)
            self.assertNotIn('fastlane', flat)
            self.assertNotIn('upload', flat)
            if platform == 'android':
                self.assertIn(':app:assembleUnsigned', flat)
                self.assertNotIn('assembleRelease', flat)
            else:
                self.assertIn('CODE_SIGNING_ALLOWED=NO', flat)
                self.assertNotIn('-allowProvisioningUpdates', flat)


    @unittest.skipUnless((ROOT / 'upstream/.git').exists(), 'fetch pinned upstream first')
    def test_prepare_changes_identity_label_and_retains_notices(self):
        with tempfile.TemporaryDirectory() as d:
            source = pathlib.Path(d) / 'source'
            subprocess.run(['git', '-c', 'advice.detachedHead=false', 'clone', '--shared', '--quiet', str(ROOT / 'upstream'), str(source)], check=True)
            before = (source / 'NOTICE.txt').read_bytes()
            result = self.run_tool('prepare', '--source', source, '--config', ROOT / 'config/app.example.json')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('applicationId "org.example.digitaltwin"', (source / 'android/app/build.gradle').read_text())
            self.assertIn('name="app_name">Digitaltwin<', (source / 'android/app/src/main/res/values/strings.xml').read_text())
            self.assertIn('<string>Digitaltwin</string>', (source / 'ios/Mattermost/Info.plist').read_text())
            self.assertNotIn('com.mattermost.rnbeta', (source / 'ios/Mattermost.xcodeproj/project.pbxproj').read_text())
            self.assertEqual(before, (source / 'NOTICE.txt').read_bytes())
            self.assertFalse((source / 'android/app/google-services.json').exists())
            self.assertEqual(self.run_tool('verify-prepared', '--source', source).returncode, 0)
            # Reject an unrecorded source edit before executing a native build.
            (source / 'app/constants/device.ts').write_text('changed')
            changed = self.run_tool('verify-prepared', '--source', source)
            self.assertNotEqual(changed.returncode, 0)
            self.assertIn('unrecorded source changes', changed.stderr)


    def test_restricted_sentry_build_tools_are_removed_without_touching_sdk(self):
        with tempfile.TemporaryDirectory() as d:
            source = pathlib.Path(d)
            cli = source / 'node_modules/@sentry/cli'
            cli.mkdir(parents=True)
            (cli / 'package.json').write_text(json.dumps({'name': '@sentry/cli', 'version': '3.4.1', 'license': 'FSL-1.1-MIT'}))
            (cli / 'binary').write_text('fixture')
            sdk = source / 'node_modules/@sentry/core'
            sdk.mkdir(parents=True)
            (sdk / 'LICENSE').write_text('fixture MIT')
            (source / 'package-lock.json').write_text(json.dumps({'packages': {'node_modules/@sentry/cli': {'version': '3.4.1', 'license': 'FSL-1.1-MIT'}, 'node_modules/@sentry/core': {'version': '10.0.0', 'license': 'MIT'}}}))
            result = subprocess.run(['python3', str(ROOT / 'bin/exclude-build-tools'), str(source)], text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse(cli.exists())
            self.assertTrue((sdk / 'LICENSE').exists())

if __name__ == '__main__':
    unittest.main()

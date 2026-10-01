"""Structural APK fixtures; no signing keys or native-build claim."""
import importlib.util
import io
from pathlib import Path
import struct
import subprocess
import shutil
import json
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]

def validate(path):
    spec = importlib.util.spec_from_file_location('unsigned_apk', ROOT / 'bin/unsigned_apk.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.assert_unsigned_apk(path)

def apk_bytes(extra=None):
    output = io.BytesIO()
    with zipfile.ZipFile(output, 'w', zipfile.ZIP_STORED) as archive:
        archive.writestr('AndroidManifest.xml', b'fixture manifest; not an installable app')
        archive.writestr('classes.dex', b'fixture bytecode')
        for name, value in (extra or {}).items():
            archive.writestr(name, value)
    return output.getvalue()

def with_signing_gap(data, gap):
    end = data.rfind(b'PK\x05\x06')
    central = struct.unpack_from('<I', data, end + 16)[0]
    altered = bytearray(data[:central] + gap + data[central:])
    struct.pack_into('<I', altered, end + len(gap) + 16, central + len(gap))
    return bytes(altered)

class UnsignedApkTests(unittest.TestCase):
    def check_bytes(self, data):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'fixture.apk'
            path.write_bytes(data)
            validate(path)

    def test_accepts_unsigned_contiguous_zip(self):
        self.check_bytes(apk_bytes())

    def test_rejects_v1_signature_markers_even_with_corrupt_signature(self):
        for name in ['META-INF/CERT.RSA', 'META-INF/CERT.SF', 'META-INF/CERT.EC', 'META-INF/MANIFEST.MF']:
            with self.subTest(name=name), self.assertRaises(ValueError):
                self.check_bytes(apk_bytes({name: b'corrupt signature fixture'}))

    def test_rejects_v2_v3_signing_block_and_corrupted_magic(self):
        for gap in [b'APK Sig Block 42', b'broken signing block magic', b'\x00' * 32]:
            with self.subTest(gap=gap), self.assertRaises(ValueError):
                self.check_bytes(with_signing_gap(apk_bytes(), gap))

    def test_rejects_tampered_zip_payload_crc(self):
        data = apk_bytes().replace(b'fixture bytecode', b'tamperedbytecode')
        with self.assertRaises(ValueError):
            self.check_bytes(data)

    def test_rejects_malformed_and_trailing_archives(self):
        for data in [b'DOES NOT VERIFY', apk_bytes()[:-4], apk_bytes() + b'trailing signature data']:
            with self.subTest(data=data[:20]), self.assertRaises(ValueError):
                self.check_bytes(data)


    @unittest.skipUnless((ROOT / 'upstream/.git').exists(), 'fetch pinned upstream first')
    def test_collector_packages_unsigned_fixture_and_rejects_tampered_signed_fixture(self):
        with tempfile.TemporaryDirectory() as directory:
            component = Path(directory) / 'mobile-apps'
            component.mkdir()
            shutil.copytree(ROOT / 'bin', component / 'bin', ignore=shutil.ignore_patterns('__pycache__'))
            shutil.copy(ROOT / 'source.lock.json', component / 'source.lock.json')
            source = component / 'upstream'
            subprocess.run(['git', '-c', 'advice.detachedHead=false', 'clone', '--shared', '--quiet', str(ROOT / 'upstream'), str(source)], check=True)
            prepared = subprocess.run(['python3', str(component / 'bin/mobile'), 'prepare', '--config', str(ROOT / 'config/app.example.json')], capture_output=True, text=True)
            self.assertEqual(prepared.returncode, 0, prepared.stderr)
            artifact = component / 'unsigned-fixture.apk'
            original = apk_bytes()
            artifact.write_bytes(original)
            result = subprocess.run(['python3', str(component / 'bin/package-unsigned'), str(artifact)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            archive = component / 'dist/unsigned-fixture-unsigned-review.zip'
            with zipfile.ZipFile(archive) as output:
                self.assertEqual(output.read('artifacts/unsigned-fixture.apk'), original)
                self.assertEqual(output.read('notices/NOTICE.txt'), (source / 'NOTICE.txt').read_bytes())
                self.assertFalse(json.loads(output.read('provenance.json'))['device_delivery_verified'])
            bad = component / 'corrupted-signed-fixture.apk'
            bad.write_bytes(with_signing_gap(apk_bytes(), b'corrupted signing block'))
            rejected = subprocess.run(['python3', str(component / 'bin/package-unsigned'), str(bad)], capture_output=True, text=True)
            self.assertNotEqual(rejected.returncode, 0)
            self.assertIn('signature absence not established', rejected.stderr)
            self.assertFalse((component / 'dist/corrupted-signed-fixture-unsigned-review.zip').exists())

if __name__ == '__main__':
    unittest.main()

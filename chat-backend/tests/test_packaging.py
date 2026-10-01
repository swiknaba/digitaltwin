import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class PackagingTests(unittest.TestCase):
    def test_final_stage_does_not_inherit_upstream_layers_or_build_tools(self):
        dockerfile = (ROOT / 'Dockerfile').read_text()
        final = dockerfile.split('FROM scratch\n', 1)[1]
        self.assertIn('COPY --from=pruned /output/ /', final)
        self.assertNotIn('busybox', final)
        self.assertIn('USER mattermost', final)
        self.assertIn('"/mattermost/bin/mmctl", "system", "status", "--local"', final)
        self.assertNotIn('8067', final)
        self.assertNotIn('8074', final)

    def test_pins_match_dockerfile(self):
        lock = json.loads((ROOT / 'artifact.lock.json').read_text())
        dockerfile = (ROOT / 'Dockerfile').read_text()
        self.assertIn(lock['image'] + '@' + lock['linux_amd64_digest'], dockerfile)
        self.assertIn(lock['build_tool']['image'] + '@' + lock['build_tool']['linux_amd64_digest'], dockerfile)


if __name__ == '__main__':
    unittest.main()

import copy
import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('contracts', ROOT / 'lib/contracts.py')
contracts = importlib.util.module_from_spec(spec)
spec.loader.exec_module(contracts)


class ContractTests(unittest.TestCase):
    def setUp(self):
        self.fixture = json.loads((ROOT / 'fixtures/thread-recovery.json').read_text())
        self.post = self.fixture['reply']

    def verify(self, post=None, member=None, root=None, user=None):
        return contracts.verify_post(post or self.post, root or self.fixture['root'],
                                     member or self.fixture['member'], user or self.fixture['human'],
                                     self.fixture['channel_id'], self.fixture['local_bot_ids'])

    def test_ordinary_reply_routes_to_verified_root(self):
        result = self.verify()
        self.assertEqual(result['thread_id'], self.fixture['root']['id'])
        self.assertNotIn('@', self.post['message'])
        self.assertFalse(result['bot'])

    def test_channel_mismatch_rejected(self):
        post = copy.deepcopy(self.post)
        post['channel_id'] = 'z' * 26
        with self.assertRaises(ValueError):
            self.verify(post=post)

    def test_root_from_other_channel_rejected(self):
        root = copy.deepcopy(self.fixture['root'])
        root['channel_id'] = 'z' * 26
        with self.assertRaises(ValueError):
            self.verify(root=root)

    def test_non_root_thread_target_rejected(self):
        root = copy.deepcopy(self.fixture['root'])
        root['root_id'] = 'z' * 26
        with self.assertRaises(ValueError):
            self.verify(root=root)

    def test_membership_and_user_identity_rejected(self):
        for key in ('user_id', 'channel_id'):
            member = copy.deepcopy(self.fixture['member'])
            member[key] = 'z' * 26
            with self.assertRaises(ValueError):
                self.verify(member=member)
        user = copy.deepcopy(self.fixture['human'])
        user['id'] = 'z' * 26
        with self.assertRaises(ValueError):
            self.verify(user=user)

    def test_local_bot_loop_suppressed_even_if_user_flag_false(self):
        post = copy.deepcopy(self.post)
        post['user_id'] = self.fixture['local_bot_ids'][0]
        user = {'id': post['user_id'], 'is_bot': False}
        member = dict(self.fixture['member'], user_id=post['user_id'])
        with self.assertRaises(ValueError):
            self.verify(post=post, user=user, member=member)

    def test_peer_bot_cannot_be_human(self):
        user = dict(self.fixture['human'], is_bot=True)
        self.assertTrue(self.verify(user=user)['bot'])

    def test_authenticated_user_false_bot_flag_may_be_omitted(self):
        self.assertFalse(self.verify(user={'id': self.post['user_id']})['bot'])
        with self.assertRaises(ValueError):
            self.verify(user={'id': self.post['user_id'], 'is_bot': 'false'})

    def test_deleted_reply_or_root_rejected(self):
        for which in ('post', 'root'):
            value = copy.deepcopy(self.post if which == 'post' else self.fixture['root'])
            value['delete_at'] = 2000
            with self.assertRaises(ValueError):
                self.verify(**{which: value})

    def test_revision_identity_deduplicates_overlap_but_preserves_edit(self):
        original = contracts.event_key(self.post)
        same = contracts.event_key(copy.deepcopy(self.post))
        edited = dict(self.post, update_at=self.post['update_at'] + 10)
        self.assertEqual(original, same)
        self.assertNotEqual(original, contracts.event_key(edited))
        self.assertNotEqual(original, contracts.event_key(self.post, 'post_deleted'))

    def test_websocket_post_is_json_string_and_seq_not_identity(self):
        event = self.fixture['posted_event']
        self.assertEqual(contracts.event_post(event), self.post)
        copied = dict(event, seq=0)
        self.assertEqual(contracts.event_key(contracts.event_post(copied)), contracts.event_key(self.post))
        copied = copy.deepcopy(event)
        copied['broadcast']['channel_id'] = 'z' * 26
        with self.assertRaises(ValueError):
            contracts.event_post(copied)

    def test_postlist_validates_map_keys_and_cross_channel(self):
        posts = contracts.history_posts(self.fixture['backfill'], self.fixture['channel_id'])
        self.assertEqual(len(posts), 2)
        invalid = copy.deepcopy(self.fixture['backfill'])
        invalid['posts'][self.post['id']]['id'] = 'z' * 26
        with self.assertRaises(ValueError):
            contracts.history_posts(invalid, self.fixture['channel_id'])

    def test_since_overlap_query_preserves_milliseconds(self):
        self.assertEqual(contracts.backfill_path('c' * 26, 10000, overlap_ms=1000),
                         '/api/v4/channels/' + 'c' * 26 + '/posts?since=9000&collapsedThreads=false')
        with self.assertRaises(ValueError):
            contracts.backfill_path('../bad', 10000)

    def test_safe_config_excludes_all_plugin_execution(self):
        config = json.loads((ROOT / 'config/phase0.json').read_text())
        for key in ('Enable', 'EnableUploads', 'EnableMarketplace', 'EnableRemoteMarketplace', 'AutomaticPrepackagedPlugins'):
            self.assertIs(config['PluginSettings'][key], False)
        self.assertEqual(config['PluginSettings']['PluginStates'], {})
        self.assertIs(config['ServiceSettings']['EnableLocalMode'], True)
        self.assertIs(config['ServiceSettings']['EnableBotAccountCreation'], False)


if __name__ == '__main__':
    unittest.main()

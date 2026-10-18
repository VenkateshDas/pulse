import unittest
from memory import PulseMemoryStore, validate_memory


class MemoryWorkspaceTests(unittest.IsolatedAsyncioTestCase):
    def test_validation_trims_and_preserves_limits(self):
        self.assertEqual(
            {'content': 'Concise replies', 'evidence': 'User requested', 'kind': 'preference'},
            validate_memory(' Concise replies ', ' User requested ', ' preference '))
        self.assertEqual(400, len(validate_memory('x' * 400, 'y' * 400)['content']))
        for args in [('', 'evidence'), ('content', ''), ('content', 'evidence', 'other'),
                     ('x' * 401, 'evidence'), ('content', 'y' * 401), (None, 'evidence'),
                     ('lesson', 'Action succeeded', 'lesson')]:
            with self.subTest(args=args), self.assertRaises(ValueError):
                validate_memory(*args)
        self.assertEqual('lesson', validate_memory('Improved', 'BEFORE slow; AFTER responsive', 'lesson')['kind'])

    def test_validation_filters_content_and_evidence(self):
        for forbidden in ['sk-fixture-secret', 'Bearer fixture', 'api_key=fixture',
                          'password:fixture', '/Users/name/file', '/Applications/App.app',
                          '-----BEGIN PRIVATE KEY-----']:
            for args in [(forbidden, 'Requested'), ('Requested', forbidden)]:
                with self.subTest(args=args), self.assertRaises(ValueError):
                    validate_memory(*args)

    async def test_disabled_edit_save_and_recall_do_not_touch_store(self):
        memory = PulseMemoryStore('s', False, store=object())
        self.assertEqual([], memory.recall())
        self.assertEqual({'error': 'Memory disabled'}, await memory.save_pulse_memory('x', 'y'))
        self.assertEqual({'error': 'Memory disabled'}, await memory.edit_memory('id', 'x', 'y', 'preference', 1))

    async def test_edit_passes_validated_payload_and_revision_only(self):
        class Store:
            def update_memory(self, identifier, payload, revision):
                self.received = (identifier, payload, revision)
                return {'status': 'Updated', 'revision': revision + 1}
        store = Store()
        memory = PulseMemoryStore('new-session', store=store)
        result = await memory.edit_memory('id', ' preference ', ' user asked ', ' preference ', 4)
        self.assertEqual({'status': 'Updated', 'revision': 5}, result)
        self.assertEqual(('id', {'content': 'preference', 'evidence': 'user asked', 'kind': 'preference'}, 4), store.received)
        self.assertIn('error', await memory.edit_memory('id', 'x', '/Users/private', 'preference', 5))
        self.assertEqual(4, store.received[2])

    def test_explicit_instructions_are_bounded_separate_untrusted_context(self):
        class Store:
            def setting(self, key, default):
                self.request = (key, default)
                return ' Prefer concise answers '
        store = Store()
        enabled = PulseMemoryStore('s', store=store)
        disabled = PulseMemoryStore('s', False, store=store)
        self.assertIn('400 characters', enabled.instructions())
        self.assertIn('before and after', enabled.instructions())
        instructions = disabled.instructions()
        self.assertIn('apply even when memory is disabled', instructions)
        self.assertIn('untrusted context', instructions)
        self.assertIn('approval requirements', instructions)
        self.assertIn('"Prefer concise answers"', instructions)
        self.assertNotIn('save_pulse_memory', instructions)
        self.assertEqual(('user_instructions', ''), store.request)
        store.setting = lambda key, default: '界' * 5000
        self.assertLessEqual(len(enabled.user_instructions().encode('utf-8')), 6000)
        store.setting = lambda key, default: ''
        self.assertEqual('', disabled.instructions())


if __name__ == '__main__':
    unittest.main()

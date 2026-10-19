import json
import unittest
import uuid
from unittest.mock import AsyncMock, patch
from pulse_toolkit import PulseToolkit


class AutomationToolTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.toolkit = PulseToolkit('run', 'session')
        self.toolkit._run_cmd = AsyncMock(return_value={'status': 'saved'})

    async def test_closed_native_routes_and_mutation_registration(self):
        await self.toolkit.list_automations()
        self.toolkit._run_cmd.assert_awaited_once_with(['automation', 'list'])
        await self.toolkit.create_automation(' Morning health ', ' Review evidence ', ' Asia/Kolkata ', 'weekly', 8, 30, 2)
        arguments = self.toolkit._run_cmd.await_args.args[0]
        self.assertEqual(['automation', 'create'], arguments[:2])
        self.assertEqual({'title': 'Morning health', 'instructions': 'Review evidence', 'repeatRule': 'weekly',
                          'hour': 8, 'minute': 30, 'weekday': 2, 'timezoneID': 'Asia/Kolkata', 'onceAt': ''}, json.loads(arguments[2]))
        identifier = str(uuid.uuid4())
        await self.toolkit.set_automation_enabled(identifier, False)
        arguments = self.toolkit._run_cmd.await_args.args[0]
        self.assertEqual(['automation', 'set_enabled'], arguments[:2])
        self.assertEqual({'id': identifier, 'enabled': False}, json.loads(arguments[2]))
        registered = {tool.__name__ for tool in self.toolkit.tools}
        self.assertTrue({'list_automations', 'create_automation', 'set_automation_enabled'} <= registered)
        self.assertTrue({'create_automation', 'set_automation_enabled'} <= self.toolkit.mutations)
        self.assertNotIn('list_automations', self.toolkit.mutations)

    async def test_invalid_create_never_reaches_native(self):
        valid = {'title': 'Health', 'instructions': 'Review evidence', 'timezone_id': 'Asia/Kolkata'}
        invalid = [{'title': ''}, {'title': 'x' * 81}, {'instructions': ''}, {'instructions': '界' * 834},
                   {'timezone_id': ''}, {'timezone_id': ' '}, {'timezone_id': 'x' * 101},
                   {'repeat_rule': 'hourly'}, {'repeat_rule': []}, {'hour': True}, {'hour': 24}, {'hour': -1},
                   {'minute': False}, {'minute': 60}, {'minute': 0.5}, {'weekday': 0}, {'weekday': 8},
                   {'weekday': True}, {'repeat_rule': 'once'}, {'once_at': 'x' * 101}, {'once_at': None}]
        for changes in invalid:
            with self.subTest(changes=changes):
                self.assertIn('error', await self.toolkit.create_automation(**{**valid, **changes}))
        # Escaped JSON may exceed transport size even when text bytes fit.
        self.assertIn('error', await self.toolkit.create_automation(**{**valid, 'instructions': '\x00' * 1000}))
        with self.assertRaises(TypeError):
            await self.toolkit.create_automation('Health', 'Review evidence')
        self.toolkit._run_cmd.assert_not_awaited()

    async def test_once_date_delegates_final_validation_to_native(self):
        timestamp = '2027-01-15T09:00:00+05:30'
        await self.toolkit.create_automation('Once', 'Review', 'Asia/Kolkata', repeat_rule='once', once_at=timestamp)
        self.assertEqual(timestamp, json.loads(self.toolkit._run_cmd.await_args.args[0][2])['onceAt'])

    async def test_invalid_toggle_never_reaches_native(self):
        for identifier, enabled in [('not-a-uuid', True), (None, True), (str(uuid.uuid4()), 1), (str(uuid.uuid4()), 'true')]:
            with self.subTest(identifier=identifier, enabled=enabled):
                self.assertIn('error', await self.toolkit.set_automation_enabled(identifier, enabled))
        self.toolkit._run_cmd.assert_not_awaited()

    def test_approval_evidence_discloses_future_costs_and_authority(self):
        arguments = {'title': 'Morning health', 'timezone_id': 'Asia/Kolkata'}
        for name in ['create_automation', 'set_automation_enabled']:
            result = self.toolkit.approval_evidence(name, arguments)
            self.assertEqual(arguments, result['arguments'])
            for text in ['may incur charges', 'while Pulse is open', 'read-only', 'approval']:
                self.assertIn(text, result['notice'])

    async def test_native_transport_uses_rpc_without_subprocess(self):
        toolkit = PulseToolkit('run', 'session')
        with patch('pulse_toolkit.native_request', new=AsyncMock(return_value={'json': '{"automations":[]}', 'exit_code': 0})) as native:
            self.assertEqual({'automations': []}, await toolkit.list_automations())
            native.assert_awaited_once_with('run', 'session', ['automation', 'list'], 30)


if __name__ == '__main__':
    unittest.main()

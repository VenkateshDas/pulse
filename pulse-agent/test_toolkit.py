import asyncio, unittest
from unittest.mock import AsyncMock, patch
from pulse_toolkit import PulseToolkit

class ToolkitTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self): self.toolkit = PulseToolkit(run_id='run', session_id='session')
    async def test_partial_failure_retains_evidence(self):
        with patch('pulse_toolkit.native_request', new=AsyncMock(return_value={'json':'{"affectedPaths":["fixture"],"failures":{"other":"denied"}}','exit_code':1})):
            result = await self.toolkit._run_cmd(['clean'])
        self.assertEqual(1,result['exitCode']); self.assertEqual(['fixture'],result['affectedPaths']); self.assertIn('other',result['failures'])
    async def test_preview_failure_does_not_authorize(self):
        with patch.object(self.toolkit,'_run_cmd',new=AsyncMock(return_value={'failures':{'fixture':'denied'}})):
            await self.toolkit.preview_cleanup('fixture')
        self.assertIn('error',await self.toolkit.clean_target('fixture'))
    async def test_changed_preview_blocks_commit(self):
        with patch.object(self.toolkit,'_run_cmd',new=AsyncMock(side_effect=[{'affectedPaths':['a']},{'affectedPaths':['b']}])) as rpc:
            await self.toolkit.preview_cleanup('fixture')
            result=await self.toolkit.clean_target('fixture')
        self.assertIn('changed',result['error']); self.assertEqual(2,rpc.await_count)
    async def test_matching_preview_is_consumed_and_scoped_to_run(self):
        with patch.object(self.toolkit,'_run_cmd',new=AsyncMock(return_value={'affectedPaths':['a']})) as rpc:
            await self.toolkit.preview_cleanup('fixture')
            await self.toolkit.clean_target('fixture')
            self.assertEqual(['clean','--target','fixture','--yes'],rpc.call_args.args[0])
            self.assertIn('error',await self.toolkit.clean_target('fixture'))
        other=PulseToolkit(run_id='other',session_id='session')
        self.assertIn('error',await other.clean_target('fixture'))
    async def test_history_discloses_limits(self):
        data={'metrics':{'cpu':[{'minute':i} for i in range(100)]},'anomalies':list(range(30)),'batterySessions':list(range(15))}
        with patch.object(self.toolkit,'_run_cmd',new=AsyncMock(return_value=data)):
            result=await self.toolkit.get_diagnostic_history()
        self.assertEqual(40,result['metrics']['cpu'][0]['minute']); self.assertEqual(100,result['agentOutputLimits']['metrics']['cpu']['observedMinutes'])
    async def test_observation_bounds_timeout(self):
        self.assertIn('error',await self.toolkit.observe_performance(601))
        with patch.object(self.toolkit,'_run_cmd',new=AsyncMock(return_value={})) as rpc:
            await self.toolkit.observe_performance(60); rpc.assert_awaited_once_with(['observe','--seconds','60'],timeout=80)
    async def test_read_cache_and_mutation_no_retry(self):
        with patch('pulse_toolkit.native_request',new=AsyncMock(return_value={'json':'{}','exit_code':0})) as rpc:
            await self.toolkit.get_vitals(); await self.toolkit.get_vitals(); self.assertEqual(1,rpc.await_count)
            await self.toolkit._run_cmd(['display','set','0.5']); await self.toolkit._run_cmd(['display','set','0.5']); self.assertEqual(3,rpc.await_count)

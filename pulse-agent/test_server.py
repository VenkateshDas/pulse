import asyncio, json, tempfile, unittest, uuid
from unittest.mock import patch, AsyncMock
from agno.run.agent import RunOutput, RunPausedEvent, RunContentEvent, RunErrorEvent
from agno.run.requirement import RunRequirement
from agno.models.response import ToolExecution
from fastapi import HTTPException
from providers import ProviderConfiguration
import server

class HarnessTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self): server.runs.clear(); server.session_writers.clear()
    def record(self, paused=False):
        class Agent:
            cancel_run=lambda *a:True
            def acontinue_run(self, **kwargs):
                async def stream(): yield RunOutput(content='Done')
                return stream()
        r=server.Run(str(uuid.uuid4()),str(uuid.uuid4()),Agent(),ProviderConfiguration())
        if paused:
            req=RunRequirement(tool_execution=ToolExecution(tool_name='clean_target',tool_args={'target_id':'fixture'},requires_confirmation=True))
            r.paused=RunOutput(run_id=r.id,session_id=r.session_id,requirements=[req])
            r.approval_id=req.id
        server.runs[r.id]=r; server.session_writers[r.session_id]=r.id
        return r
    async def test_pause_retains_run_output_and_arguments(self):
        r=self.record(); req=RunRequirement(tool_execution=ToolExecution(tool_name='clean_target',tool_args={'target_id':'fixture'},requires_confirmation=True))
        async def stream():
            yield RunPausedEvent()
            yield RunOutput(run_id=r.id,session_id=r.session_id,requirements=[req])
        lines=[x async for x in server.translate(stream(),r)]
        self.assertIsInstance(r.paused,RunOutput); self.assertEqual(req.id,r.approval_id)
        self.assertIn('fixture',lines[0]); self.assertIn('approval.requested',lines[0])
    async def test_single_requirement_and_duplicate_resolution(self):
        r=self.record(True)
        req2=RunRequirement(tool_execution=ToolExecution(tool_name='uninstall_app',tool_args={'app_path_or_name':'other'},requires_confirmation=True))
        r.paused.requirements.append(req2)
        first=r.approval_id
        response=await server.continue_run(r.id,server.ContinueRequest(approved=True,approval_id=first))
        lines=[x async for x in response.body_iterator]
        self.assertEqual(req2.id,r.approval_id); self.assertFalse(req2.is_resolved())
        with self.assertRaises(HTTPException): await server.continue_run(r.id,server.ContinueRequest(approved=True,approval_id=first))
        response=await server.continue_run(r.id,server.ContinueRequest(approved=False,approval_id=req2.id))
        lines=[x async for x in response.body_iterator]
        self.assertTrue(r.terminal); self.assertNotIn(r.session_id,server.session_writers)
    async def test_cancel_stops_active_task(self):
        r=self.record()
        r.task=asyncio.create_task(asyncio.sleep(60))
        with patch('server.native_request',new=AsyncMock(return_value={})):
            await server.cancel(r.id)
        await asyncio.sleep(0)
        self.assertTrue(r.cancelled); self.assertTrue(r.task.cancelled())
    async def test_replay_is_bounded_and_reports_gap(self):
        r=self.record()
        for _ in range(server.MAX_EVENTS+10): server.event_line(r,'tool.completed',{'detail':'x'})
        self.assertEqual(server.MAX_EVENTS,len(r.events))
        with self.assertRaises(HTTPException) as e: await server.replay(r.id,0)
        self.assertEqual(410,e.exception.status_code)
    async def test_provider_run_error_never_becomes_success(self):
        r=self.record()
        async def stream(): yield RunErrorEvent(content="fixture")
        with self.assertRaises(RuntimeError):
            _=[x async for x in server.translate(stream(),r)]
        self.assertFalse(r.terminal)

    async def test_long_delta_is_not_silently_truncated(self):
        r=self.record()
        async def stream(): yield RunContentEvent(content='x'*2000)
        lines=[x async for x in server.translate(stream(),r)]
        final=next(json.loads(x.split('data: ')[1]) for x in lines if 'answer.final' in x)
        self.assertEqual(2000,len(final['payload']['text']))

class ProviderTests(unittest.TestCase):
    def test_local_no_key_and_url_validation(self):
        self.assertTrue(ProviderConfiguration(base_url='http://127.0.0.1:1234/v1').ready)
        self.assertFalse(ProviderConfiguration().ready)
        for url in ['http://remote.example/v1','https://user:secret@remote.example','https://remote.example?key=x']:
            with self.assertRaises(ValueError): ProviderConfiguration(base_url=url)
    def test_explicit_provider_wins_over_environment(self):
        with patch.dict('os.environ',{'ANTHROPIC_API_KEY':'fixture'}):
            self.assertEqual('OpenAIChat',type(ProviderConfiguration().make_model()).__name__)

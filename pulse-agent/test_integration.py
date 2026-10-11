"""Actual Agno streaming/tool/summary/storage lifecycle with a local fake model."""
import json, tempfile, unittest, uuid
from unittest.mock import AsyncMock, patch
from agno.models.openai import OpenAIChat
from agno.models.response import ModelResponse
from openai.types.chat.chat_completion_chunk import ChoiceDeltaToolCall
from agno.metrics import MessageMetrics
from agno.db.base import SessionType
from agent import create_pulse_agent
from providers import ProviderConfiguration
import server

class FixtureModel(OpenAIChat):
    async def ainvoke_stream(self, messages, assistant_message, **kwargs):
        if messages[-1].role == 'user':
            yield ModelResponse(role='assistant', tool_calls=[ChoiceDeltaToolCall(index=0,id=str(uuid.uuid4()),type='function',function={'name':'read_current_context','arguments':'{}'})])
        else:
            yield ModelResponse(role='assistant', content='Native evidence received. No mutation performed.')
    async def ainvoke(self, messages, **kwargs):
        return ModelResponse(role='assistant', content='{"summary":"Verified fixture evidence, no mutation.","topics":["fixture"]}')

class AgnoIntegrationTests(unittest.IsolatedAsyncioTestCase):
    async def test_real_stream_tools_persistence_and_checkpoint_summary(self):
        with tempfile.TemporaryDirectory() as d:
            sid=str(uuid.uuid4())
            with patch('pulse_toolkit.native_request',new=AsyncMock(return_value={'json':'{"timestamp":"fixture","cpu":12}','exit_code':0})) as rpc:
                for index in range(4):
                    rid=str(uuid.uuid4())
                    instance=create_pulse_agent(session_id=sid,run_id=rid,db_path=d+'/agent.db',
                        model=FixtureModel(id='fixture'),configuration=ProviderConfiguration(memory_enabled=False))
                    r=server.Run(rid,sid,instance,ProviderConfiguration());r.message='Check current context'
                    lines=[line async for line in server.serve(r)]
                    kinds=[json.loads(line.split('data: ')[1])['kind'] for line in lines]
                    self.assertIn('tool.started',kinds);self.assertIn('tool.completed',kinds)
                    self.assertIn('answer.final',kinds);self.assertEqual('run.completed',kinds[-1])
                self.assertEqual(4,rpc.await_count)
            stored=instance.db.get_session(sid,session_type=SessionType.AGENT)
            self.assertEqual(4,len(stored.runs));self.assertIsNotNone(stored.summary)
            messages=stored.get_messages(skip_roles=['system','tool'])
            users=[m for m in messages if m.role=='user']
            self.assertEqual(4,len(users))

    async def test_large_tool_result_preserves_dialogue_after_restart(self):
        class RecallModel(FixtureModel):
            async def ainvoke_stream(self, messages, assistant_message, **kwargs):
                if messages[-1].content == 'Recall earlier answer':
                    self.asserted_history = any(m.role == 'assistant' and m.content == 'Native evidence received. No mutation performed.' for m in messages[:-1])
                    yield ModelResponse(role='assistant', content='Recalled')
                else:
                    async for chunk in super().ainvoke_stream(messages, assistant_message, **kwargs): yield chunk
        with tempfile.TemporaryDirectory() as d:
            sid = str(uuid.uuid4())
            config = ProviderConfiguration(memory_enabled=False)
            with patch('pulse_toolkit.native_request', new=AsyncMock(return_value={'json': 'x' * 24000, 'exit_code': 0})):
                first = create_pulse_agent(session_id=sid, db_path=d+'/agent.db', model=FixtureModel(id='fixture'), configuration=config)
                async for _ in first.arun('Read context', stream=True): pass
            model = RecallModel(id='fixture')
            restarted = create_pulse_agent(session_id=sid, db_path=d+'/agent.db', model=model, configuration=config)
            async for _ in restarted.arun('Recall earlier answer', stream=True): pass
            self.assertTrue(model.asserted_history)

    async def test_actual_agno_approval_pauses_and_resumes_once(self):
        class ApprovalModel(FixtureModel):
            async def ainvoke_stream(self, messages, assistant_message, **kwargs):
                if messages[-1].role == 'user':
                    yield ModelResponse(role='assistant',tool_calls=[ChoiceDeltaToolCall(index=0,id='fixture-action',type='function',function={'name':'set_keep_awake','arguments':'{"until_seconds":60}'})])
                else: yield ModelResponse(role='assistant',content='Approved fixture action completed.')
        with tempfile.TemporaryDirectory() as d:
            sid,rid=str(uuid.uuid4()),str(uuid.uuid4())
            instance=create_pulse_agent(session_id=sid,run_id=rid,db_path=d+'/agent.db',model=ApprovalModel(id='fixture'),configuration=ProviderConfiguration(memory_enabled=False))
            r=server.Run(rid,sid,instance,ProviderConfiguration());r.message='Enable fixture keep awake'
            server.runs[rid]=r;server.session_writers[sid]=rid
            try:
                with patch('pulse_toolkit.native_request',new=AsyncMock(return_value={'json':'{"ok":true}','exit_code':0})) as rpc:
                    lines=[line async for line in server.serve(r)]
                    self.assertIsNotNone(r.paused);self.assertIsNotNone(r.approval_id)
                    self.assertTrue(any('approval.requested' in line for line in lines))
                    self.assertEqual(0,rpc.await_count)
                    response=await server.continue_run(rid,server.ContinueRequest(approved=True,approval_id=r.approval_id))
                    continued=[line async for line in response.body_iterator]
                    self.assertTrue(r.terminal);self.assertEqual(1,rpc.await_count)
                    self.assertTrue(any('run.completed' in line for line in continued))
            finally: server.runs.pop(rid,None);server.session_writers.pop(sid,None)

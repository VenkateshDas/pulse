"""Real pinned OpenWorker loop + Pulse native bridge/storage, without model network calls."""
import asyncio
import json
import tempfile
import unittest
import uuid
from unittest.mock import AsyncMock, patch
from coworker.engine import TurnEngine
from coworker.providers.base import AssistantTurn, ModelCapabilities, ProviderClient, StreamChunk, ToolCall
from conversation_store import ConversationStore
from openworker_runtime import PulseTurnEngine, estimate
from providers import ProviderConfiguration
from memory import PulseMemoryStore
import server

class FixtureProvider(ProviderClient):
    def __init__(self, action=None):self.action=action;self.calls=[]
    def capabilities(self,model):return ModelCapabilities()
    def complete(self,**kwargs):
        # Eight upstream required headings; preserve mandate and the fixture preference.
        return AssistantTurn(text='\n'.join(f'## {h}\nVerified user preference: concise answers. Continue the original task using native evidence; no action approval has been granted.' for h in
            ['Primary request','Key concepts','Artifacts and files','Errors and fixes','User messages','Pending tasks','Current work','Next step']))
    def stream(self,*,messages,**kwargs):
        self.calls.append(messages)
        if messages[-1]['role']=='user' and self.action:
            name,args=self.action
            yield StreamChunk(turn=AssistantTurn(tool_calls=[ToolCall(str(uuid.uuid4()),name,args)],finish_reason='tool_calls'))
        else:
            yield StreamChunk(text_delta='Native evidence received. ')
            yield StreamChunk(turn=AssistantTurn(text='Native evidence received. No mutation performed.',finish_reason='stop'))

class RuntimeTests(unittest.IsolatedAsyncioTestCase):
    def engine(self,directory,sid=None,provider=None,config=None):
        config=config or ProviderConfiguration(memory_enabled=False)
        store=ConversationStore(directory+'/conversations.db');sid=sid or str(uuid.uuid4())
        return PulseTurnEngine(configuration=config,store=store,session_id=sid,run_id=str(uuid.uuid4()),provider=provider or FixtureProvider(),
                               memory=PulseMemoryStore(sid,config.memory_enabled,store=store))
    async def drive(self,engine,text='Check context'):
        events=[]
        async for event in engine.run(text):
            events.append(event)
            await engine.checkpoint()
        return events
    async def test_upstream_loop_native_tools_and_restart_history(self):
        with tempfile.TemporaryDirectory() as d:
            provider=FixtureProvider(('read_current_context',{}));first=self.engine(d,provider=provider)
            self.assertIsInstance(first,TurnEngine)
            with patch('pulse_toolkit.native_request',new=AsyncMock(return_value={'json':'{"cpu":12}','exit_code':0})) as rpc:
                events=await self.drive(first)
                self.assertEqual(1,rpc.await_count)
            self.assertEqual('completed',events[-1].data['status'])
            second_provider=FixtureProvider();second=self.engine(d,sid=first.session_id,provider=second_provider)
            await self.drive(second,'What did you conclude?')
            self.assertTrue(any(m.get('content')=='Native evidence received. No mutation performed.' for m in second_provider.calls[0]))
            history=second.store.history(first.session_id)
            self.assertEqual(4,len([m for m in history['messages'] if m['role'] in {'user','assistant'}]))
    async def test_human_approval_and_duplicate_rejection(self):
        with tempfile.TemporaryDirectory() as d:
            engine=self.engine(d,provider=FixtureProvider(('set_keep_awake',{'until_seconds':60})))
            r=server.Run(engine.run_id,engine.session_id,engine,engine.configuration,message='Keep awake')
            server.session_writers[r.session_id]=r.id;server.runs[r.id]=r
            try:
                with patch('pulse_toolkit.native_request',new=AsyncMock(return_value={'json':'{"ok":true}','exit_code':0})) as rpc:
                    r.task=asyncio.create_task(server.serve(r))
                    lines=[line async for line in server.observe(r)]
                    self.assertTrue(any('approval.requested' in line for line in lines));self.assertEqual(0,rpc.await_count)
                    approval=r.approval_id
                    with self.assertRaises(server.HTTPException):
                        await server.continue_run(r.id,server.ContinueRequest(approved=True,approval_id=approval,answer='yes'))
                    self.assertEqual(0,rpc.await_count)
                    response=await server.continue_run(r.id,server.ContinueRequest(approved=True,approval_id=approval))
                    lines=[line async for line in response.body_iterator]
                    await r.task
                    self.assertTrue(r.terminal);self.assertEqual(1,rpc.await_count)
                    with self.assertRaises(server.HTTPException):await server.continue_run(r.id,server.ContinueRequest(approved=True,approval_id=approval))
            finally:
                server.runs.pop(r.id,None);server.session_writers.pop(r.session_id,None)
    async def test_read_only_mode_denies_native_mutations_and_memory(self):
        with tempfile.TemporaryDirectory() as d:
            for action in [('set_keep_awake',{'until_seconds':60}),
                           ('save_pulse_memory',{'content':'Prefer concise answers','evidence':'Explicit request'})]:
                engine=self.engine(d,provider=FixtureProvider(action),config=ProviderConfiguration(memory_enabled=True))
                engine.read_only=True
                with patch('pulse_toolkit.native_request',new=AsyncMock()) as rpc:
                    events=await self.drive(engine)
                    self.assertEqual(0,rpc.await_count)
                results=[e for e in events if e.type.value=='tool_finished']
                self.assertEqual('denied',results[0].data['status'])
                self.assertEqual([],engine.store.memory_rows())
    async def test_question_requires_answer_and_cannot_execute_native_action(self):
        with tempfile.TemporaryDirectory() as d:
            engine=self.engine(d,provider=FixtureProvider(('ask_user',{'question':'Which app?','options':['Browser','Editor']})))
            r=server.Run(engine.run_id,engine.session_id,engine,engine.configuration,message='Diagnose')
            server.runs[r.id]=r;server.session_writers[r.session_id]=r.id
            try:
                with patch('pulse_toolkit.native_request',new=AsyncMock()) as rpc:
                    r.task=asyncio.create_task(server.serve(r))
                    lines=[line async for line in server.observe(r)]
                    self.assertTrue(any('question' in line for line in lines))
                    with self.assertRaises(server.HTTPException):
                        await server.continue_run(r.id,server.ContinueRequest(approved=True,approval_id=r.approval_id))
                    response=await server.continue_run(r.id,server.ContinueRequest(approved=False,approval_id=r.approval_id,answer='Browser'))
                    _=[line async for line in response.body_iterator]
                    await r.task
                    self.assertTrue(r.terminal);self.assertEqual(0,rpc.await_count)
                    self.assertTrue(any('Browser' in str(m.get('content','')) for m in engine.messages if m.get('role')=='tool'))
            finally:
                server.runs.pop(r.id,None);server.session_writers.pop(r.session_id,None)
    async def test_nested_result_is_bounded_and_retrievable(self):
        with tempfile.TemporaryDirectory() as d:
            engine=self.engine(d)
            original={'nested':[['evidence-'+str(i)+'x'*1000] for i in range(50)]}
            event=engine._record_result(ToolCall('c','get_vitals',{}),original,'ok')
            detail=event.data['detail']
            self.assertLess(len(json.dumps(detail).encode()),6000)
            recovered='';offset=0
            while True:
                page=await engine.read_tool_result(detail['result_id'],offset)
                recovered+=page['text']
                if page['next_offset'] is None:break
                offset=page['next_offset']
            self.assertEqual(original,json.loads(recovered))
            other=self.engine(d)
            self.assertIn('error',await other.read_tool_result(detail['result_id']))
    async def test_long_conversation_compacts_and_remains_searchable(self):
        with tempfile.TemporaryDirectory() as d:
            engine=self.engine(d,config=ProviderConfiguration(context_tokens=16384,output_tokens=2048,memory_enabled=False))
            first={'role':'user','content':'Remember: the project name is copper-otter. Prefer concise answers.'}
            history=[first]
            for i in range(60):
                history.extend([{'role':'user','content':f'Question {i} '+('context '*100)},
                                {'role':'assistant','content':f'Answer {i} '+('evidence '*100)}])
            engine.store.checkpoint(engine.session_id,history,history,engine.run_id,'completed')
            restarted=self.engine(d,sid=engine.session_id,config=engine.configuration)
            before=estimate(restarted._outbound_messages(),restarted.registry.schemas())
            await self.drive(restarted,'Continue with the preference stated at the beginning.')
            after=estimate(restarted._outbound_messages(),restarted.registry.schemas())
            self.assertLess(after,before)
            found=await restarted.search_conversation('copper-otter')
            self.assertIn('copper-otter',found['matches'][0]['text'])
            again=self.engine(d,sid=engine.session_id,config=engine.configuration)
            self.assertLess(estimate(again._outbound_messages(),again.registry.schemas()),before)
    async def test_unknown_tool_fails_closed(self):
        with tempfile.TemporaryDirectory() as d:
            engine=self.engine(d,provider=FixtureProvider(('run_shell',{'command':'echo forbidden'})))
            events=await self.drive(engine)
            failed=[e for e in events if e.type.value=='tool_finished']
            self.assertEqual('error',failed[0].data['status'])
    async def test_malformed_question_returns_tool_error_without_breaking_stream(self):
        with tempfile.TemporaryDirectory() as d:
            engine=self.engine(d,provider=FixtureProvider(('ask_user',{'question':'Which app?','options':[{'unsafe':'shape'}]})))
            events=await self.drive(engine)
            self.assertFalse(any(e.type.value=='permission_required' for e in events))
            self.assertEqual('error',next(e for e in events if e.type.value=='tool_finished').data['status'])
            self.assertEqual('completed',events[-1].data['status'])
    async def test_transport_diagnostics_keep_status_without_provider_error_body(self):
        class Rejected(RuntimeError):status_code=401
        class RejectedProvider(FixtureProvider):
            def stream(self,**kwargs):raise Rejected('secret provider response body')
        with tempfile.TemporaryDirectory() as d:
            engine=self.engine(d,provider=RejectedProvider())
            with patch('openworker_runtime.record') as log:
                with self.assertRaises(Rejected):_=[chunk async for chunk in engine._astream()]
            event=next(call for call in log.call_args_list if call.args[0]=='provider.transport_failed')
            self.assertEqual(401,event.kwargs['status_code'])
            self.assertEqual('Rejected',event.kwargs['error_type'])
            self.assertNotIn('secret',str(log.call_args_list))

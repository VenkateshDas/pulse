import asyncio
import json
from pathlib import Path
import tempfile
import threading
import unittest
import uuid
from unittest.mock import AsyncMock, patch
from agno.db.sqlite import SqliteDb
from agno.session import AgentSession
from agno.run.agent import RunOutput
from agno.models.message import Message
from coworker.providers.base import AssistantTurn, StreamChunk
from conversation_store import ConversationStore
from openworker_runtime import estimate
from providers import ProviderConfiguration
import test_integration as fixtures
FixtureProvider=fixtures.FixtureProvider
import server

class RecoveryTests(unittest.IsolatedAsyncioTestCase):
    engine=fixtures.RuntimeTests.engine
    drive=fixtures.RuntimeTests.drive
    async def test_cancelled_checkpoint_finishes_transaction_before_terminal_retry(self):
        with tempfile.TemporaryDirectory() as d:
            engine=self.engine(d)
            engine.messages.append({'role':'user','content':'Keep this once'})
            started=threading.Event();release=threading.Event();original=engine.store.checkpoint
            def blocked(*args,**kwargs):
                started.set();release.wait(2);return original(*args,**kwargs)
            with patch.object(engine.store,'checkpoint',side_effect=blocked):
                pending=asyncio.create_task(engine.checkpoint())
                try:
                    self.assertTrue(await asyncio.to_thread(started.wait,1))
                    pending.cancel();await asyncio.sleep(0)
                    self.assertFalse(pending.done())
                finally:release.set()
                with self.assertRaises(asyncio.CancelledError):await pending
            await engine.checkpoint('cancelled')
            self.assertEqual(['Keep this once'],[m['content'] for m in engine.store.history(engine.session_id)['messages']])
    async def test_stop_before_first_token_preserves_partial_text_and_releases_writer(self):
        class BlockedProvider(FixtureProvider):
            def __init__(self):super().__init__();self.started=threading.Event();self.release=threading.Event()
            def stream(self,**kwargs):
                yield StreamChunk(text_delta='Partial observed answer')
                self.started.set();self.release.wait(3)
                yield StreamChunk(turn=AssistantTurn(text='Late answer must not replace partial',finish_reason='stop'))
        with tempfile.TemporaryDirectory() as d:
            provider=BlockedProvider();engine=self.engine(d,provider=provider)
            r=server.Run(engine.run_id,engine.session_id,engine,engine.configuration,message='Fixture')
            server.runs[r.id]=r;server.session_writers[r.session_id]=r.id
            try:
                r.task=asyncio.create_task(server.serve(r))
                self.assertTrue(await asyncio.to_thread(provider.started.wait,1))
                for _ in range(100):
                    if any(e['kind']=='answer.delta' for e in r.events):break
                    await asyncio.sleep(.005)
                with patch('server.native_request',new=AsyncMock(return_value={})):
                    await server.cancel(r.id)
                await asyncio.wait_for(r.task,.5)
                self.assertTrue(r.terminal);self.assertNotIn(r.session_id,server.session_writers)
                history=engine.store.history(engine.session_id)['messages']
                self.assertTrue(any(m['content']=='Partial observed answer' for m in history))
                self.assertFalse(any(m['content']=='Late answer must not replace partial' for m in history))
            finally:
                provider.release.set();server.runs.pop(r.id,None);server.session_writers.pop(r.session_id,None)
    async def test_cancel_before_setup_creates_tombstone(self):
        identifier=str(uuid.uuid4())
        await server.cancel(identifier)
        with patch('server.configuration',ProviderConfiguration(base_url='http://127.0.0.1:11434/v1')):
            with self.assertRaises(server.HTTPException) as caught:
                await server.run(server.RunRequest(message='Fixture',request_id=identifier))
        self.assertIn('stopped',caught.exception.detail)
        server.cancelled_requests.pop(identifier,None)
    async def test_reconnect_restores_unsubmitted_approval_and_decline_executes_nothing(self):
        with tempfile.TemporaryDirectory() as d:
            engine=self.engine(d,provider=FixtureProvider(('set_keep_awake',{'until_seconds':60})))
            r=server.Run(engine.run_id,engine.session_id,engine,engine.configuration,message='Fixture')
            server.runs[r.id]=r;server.session_writers[r.session_id]=r.id
            try:
                with patch('pulse_toolkit.native_request',new=AsyncMock(return_value={'json':'{}','exit_code':0})) as rpc:
                    r.task=asyncio.create_task(server.serve(r))
                    _=[line async for line in server.observe(r)]
                    approval=r.approval_id
                    response=await server.reconnect(r.id,r.sequence)
                    resumed=[line async for line in response.body_iterator]
                    self.assertTrue(any('approval.requested' in line for line in resumed))
                    self.assertEqual(approval,r.approval_id)
                    response=await server.continue_run(r.id,server.ContinueRequest(approval_id=approval,approved=False))
                    _=[line async for line in response.body_iterator];await r.task
                    self.assertEqual(0,rpc.await_count)
            finally:
                server.runs.pop(r.id,None);server.session_writers.pop(r.session_id,None)
    async def test_120_turns_reopen_compact_and_preserve_canonical_history(self):
        with tempfile.TemporaryDirectory() as d:
            provider=FixtureProvider();sid=str(uuid.uuid4())
            config=ProviderConfiguration(context_tokens=16384,output_tokens=2048,memory_enabled=False)
            for i in range(120):
                engine=self.engine(d,sid=sid,provider=provider,config=config)
                await self.drive(engine,('Original mandate: copper-otter, prefer concise answers. ' if i==0 else f'Follow-up {i}. ')+('Evidence context. '*30))
            self.assertEqual(120,len(provider.calls))
            self.assertTrue(any('compacted' in json.dumps(call).lower() for call in provider.calls))
            self.assertLessEqual(max(estimate(call,engine.registry.schemas()) for call in provider.calls),config.context_tokens-config.output_tokens)
            self.assertIn('copper-otter',(await engine.search_conversation('copper-otter'))['matches'][0]['text'])
            with engine.store.connection() as db:
                count=db.execute("SELECT count(*) FROM messages WHERE json_extract(payload,'$.role')='user'").fetchone()[0]
            self.assertEqual(120,count)

class MigrationTests(unittest.TestCase):
    def fixture(self,d):
        db=SqliteDb(db_file=d+'/legacy.db');sid=str(uuid.uuid4())
        db.upsert_session(AgentSession(session_id=sid,agent_id='pulse-agent',user_id='fixture',session_data={'session_name':'Legacy fixture'},
            runs=[RunOutput(run_id='legacy',session_id=sid,agent_id='pulse-agent',messages=[Message(role='user',content='Remember copper-otter'),Message(role='assistant',content='Remembered fixture')])]))
        db.upsert_run(RunOutput(run_id='legacy',session_id=sid,agent_id='pulse-agent',messages=[Message(role='user',content='Remember copper-otter'),Message(role='assistant',content='Remembered fixture')]),session_id=sid)
        db.upsert_learning(id=str(uuid.uuid4()),learning_type='pulse_memory',user_id='fixture',namespace='fixture',
                           content={'content':'Prefer concise answers','evidence':'Explicit user request','kind':'preference','source_session':sid,'created_at':1})
        return db,sid
    def test_actual_legacy_api_import_backup_and_idempotence(self):
        with tempfile.TemporaryDirectory() as d:
            legacy,sid=self.fixture(d);store=ConversationStore(d+'/new.db')
            store.migrate(legacy,user_id='fixture');store.migrate(legacy,user_id='fixture')
            self.assertEqual(1,len(store.sessions()));self.assertEqual(2,len(store.history(sid)['messages']))
            self.assertEqual(1,len(store.memory_rows()))
            self.assertTrue(Path(d+'/new.db.legacy-backup').is_file())
            self.assertEqual('Remember copper-otter',store.view(sid)[0]['content'])
    def test_import_failure_rolls_back_and_can_retry(self):
        with tempfile.TemporaryDirectory() as d:
            legacy,sid=self.fixture(d);store=ConversationStore(d+'/new.db')
            with patch.object(legacy,'get_learnings',side_effect=OSError('fixture disk error')):
                with self.assertRaises(OSError):store.migrate(legacy,user_id='fixture')
            self.assertEqual([],store.sessions())
            store.migrate(legacy,user_id='fixture')
            self.assertEqual(2,len(store.history(sid)['messages']))

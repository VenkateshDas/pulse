import json
import tempfile
import unittest
import uuid
from unittest.mock import patch
from conversation_store import ConversationStore
from diagnostics import configure, record, logger
from providers import ProviderConfiguration
import server

class HarnessTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):server.runs.clear();server.session_writers.clear()
    async def test_replay_bounded_and_terminal_idempotent(self):
        r=server.Run('r','s',None,ProviderConfiguration())
        server.runs[r.id]=r
        for _ in range(server.MAX_EVENTS+10):server.event_line(r,'tool.completed',{'detail':'x'})
        self.assertEqual(server.MAX_EVENTS,len(r.events))
        with self.assertRaises(server.HTTPException) as caught:await server.replay(r.id,0)
        self.assertEqual(410,caught.exception.status_code)
        server.event_line(r,'run.completed');sequence=r.sequence
        server.event_line(r,'run.failed');self.assertEqual(sequence,r.sequence)
    async def test_local_no_key_and_url_validation(self):
        self.assertTrue(ProviderConfiguration(base_url='http://127.0.0.1:1234/v1').ready)
        self.assertFalse(ProviderConfiguration().ready)
        for url in ['http://remote.example/v1','https://user:secret@remote.example','https://remote.example?key=x']:
            with self.assertRaises(ValueError):ProviderConfiguration(base_url=url)
    async def test_explicit_provider_does_not_use_foreign_environment(self):
        with patch.dict('os.environ',{'ANTHROPIC_API_KEY':'fixture'}):
            self.assertEqual('OpenAIProvider',type(ProviderConfiguration(api_key='fixture').make_provider()).__name__)
    async def test_log_allowlist_excludes_secrets_payloads_urls(self):
        with tempfile.TemporaryDirectory() as d:
            for handler in logger.handlers[:]:logger.removeHandler(handler);handler.close()
            configure(d)
            record('tool.finished',run_id='r',operation='get_vitals',elapsed_ms=12,
                   api_key='sk-private',body='private question',url='https://provider/?key=private',arguments={'secret':'x'})
            for handler in logger.handlers:handler.flush()
            from pathlib import Path
            text=Path(d+'/harness.jsonl').read_text()
            row=json.loads(text)
            self.assertEqual('r',row['run_id']);self.assertEqual(12,row['elapsed_ms'])
            self.assertNotIn('private',text);self.assertNotIn('arguments',row)
            self.assertEqual(0o600,Path(d+'/harness.jsonl').stat().st_mode&0o777)
            for handler in logger.handlers[:]:logger.removeHandler(handler);handler.close()

class StoreTests(unittest.TestCase):
    def test_uncertain_checkpoint_retry_is_idempotent_without_collapsing_repeated_text(self):
        with tempfile.TemporaryDirectory() as d:
            store=ConversationStore(d+'/state.db')
            messages=[{'role':'user','content':'Again','_pulse_message_id':str(uuid.uuid4())} for _ in range(2)]
            store.checkpoint('s',messages,messages,'r','running')
            store.checkpoint('s',messages,messages,'r','failed')
            self.assertEqual(2,len(store.history('s')['messages']))
    def test_restart_expires_pending_decisions_and_compare_and_set(self):
        with tempfile.TemporaryDirectory() as d:
            store=ConversationStore(d+'/state.db')
            identifier=store.pending('r','s','c','clean_target',{'id':'x'},{'paths':['a']})
            self.assertFalse(store.resolve(identifier,'wrong',True))
            self.assertTrue(store.resolve(identifier,'r',False))
            self.assertFalse(store.resolve(identifier,'r',True))
            other=store.pending('r','s','d','clean_target',{},{});store.recover()
            self.assertFalse(store.resolve(other,'r',True))
    def test_history_is_paginated_without_duplicates(self):
        with tempfile.TemporaryDirectory() as d:
            store=ConversationStore(d+'/state.db')
            messages=[{'role':'user','content':str(i)} for i in range(120)]
            store.checkpoint('s',messages,[],'r','completed')
            pages=[store.history('s',p) for p in (1,2,3)]
            self.assertEqual([True,True,False],[p['has_more'] for p in pages])
            self.assertEqual(120,len({m['content'] for p in pages for m in p['messages']}))

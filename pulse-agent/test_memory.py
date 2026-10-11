import tempfile, unittest
from unittest.mock import patch
from agno.db.sqlite import SqliteDb
from agno.models.message import Message
from memory import PulseMemoryStore
from budget import ContextBudgetExceeded, bound_model
from providers import ProviderConfiguration

class MemoryTests(unittest.IsolatedAsyncioTestCase):
    async def test_recall_delete_disable_and_provenance(self):
        with tempfile.TemporaryDirectory() as d:
            db=SqliteDb(db_file=d+'/memory.db')
            with patch('memory.database',return_value=db):
                first=PulseMemoryStore('session-a')
                result=await first.save_pulse_memory('Prefer concise answers','User explicitly requested concise answers')
                rows=await PulseMemoryStore('session-b').arecall()
                self.assertEqual(1,len(rows));self.assertEqual('session-a',rows[0]['source_session'])
                self.assertEqual([],await PulseMemoryStore('s',False).arecall())
                self.assertIn('error',await PulseMemoryStore('s',False).save_pulse_memory('x','y'))
                db.delete_learning(result['id'])
                self.assertEqual([],await PulseMemoryStore('s').arecall())
    async def test_secrets_paths_and_unverified_lessons_refused(self):
        store=PulseMemoryStore('s')
        for text in ['api_key=fixture','/Users/name/Documents/file','sk-fixture-secret']:
            self.assertIn('error',await store.save_pulse_memory(text,'requested'))
        self.assertIn('error',await store.save_pulse_memory('Cleanup improves performance','The tool succeeded','lesson'))
    async def test_prompt_guard_runs_before_provider(self):
        model=bound_model(ProviderConfiguration().make_model(),8192,4096)
        with self.assertRaises(ContextBudgetExceeded):
            async for _ in model.ainvoke_stream([Message(role='user',content='x'*30000)],Message(role='assistant')): pass

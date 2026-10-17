import tempfile
import unittest
from conversation_store import ConversationStore
from memory import PulseMemoryStore

class MemoryTests(unittest.IsolatedAsyncioTestCase):
    async def test_recall_delete_disable_and_provenance(self):
        with tempfile.TemporaryDirectory() as d:
            db=ConversationStore(d+'/memory.db')
            first=PulseMemoryStore('session-a',store=db)
            result=await first.save_pulse_memory('Prefer concise answers','User explicitly requested concise answers')
            rows=await PulseMemoryStore('session-b',store=db).arecall()
            self.assertEqual(1,len(rows));self.assertEqual('session-a',rows[0]['source_session'])
            self.assertEqual([],await PulseMemoryStore('s',False,store=db).arecall())
            self.assertIn('error',await PulseMemoryStore('s',False,store=db).save_pulse_memory('x','y'))
            db.delete_memory(result['id'])
            self.assertEqual([],await PulseMemoryStore('s',store=db).arecall())
    async def test_secrets_paths_and_unverified_lessons_refused(self):
        with tempfile.TemporaryDirectory() as d:
            store=PulseMemoryStore('s',store=ConversationStore(d+'/memory.db'))
            for text in ['api_key=fixture','/Users/name/Documents/file','sk-fixture-secret']:
                self.assertIn('error',await store.save_pulse_memory(text,'requested'))
            self.assertIn('error',await store.save_pulse_memory('Cleanup improves performance','The tool succeeded','lesson'))
    async def test_memory_count_limit_and_deduplication_are_transactional(self):
        import asyncio
        with tempfile.TemporaryDirectory() as d:
            store=PulseMemoryStore('s',store=ConversationStore(d+'/memory.db'))
            results=await asyncio.gather(*(store.save_pulse_memory('Preference '+str(i),'Explicit fixture preference') for i in range(105)))
            self.assertEqual(100,len(await store.arecall()))
            self.assertEqual(5,sum('error' in result for result in results))

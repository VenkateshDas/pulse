import tempfile
import unittest
from pathlib import Path
from conversation_store import ConversationStore

class WorkspaceTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.store=ConversationStore(Path(self.temp.name)/'test.db')
        self.store.checkpoint('chat',[{'role':'user','content':'Investigate memory pressure','_pulse_message_id':'a'}],[], 'run','completed','Slow Mac')

    def test_search_archive_and_manual_title_wins(self):
        self.assertEqual(self.store.sessions(query='pressure')[0]['session_id'],'chat')
        old=self.store.session_metadata('chat')['revision']
        self.store.update_session('chat',title='My title',pinned=True)
        self.assertFalse(self.store.set_generated_title('chat','Late title',old))
        self.store.update_session('chat',archived=True)
        self.assertEqual(self.store.sessions(),[])
        self.assertEqual(self.store.sessions(archived=True)[0]['name'],'My title')
        self.store.update_session('chat',archived=False)
        self.assertTrue(self.store.sessions()[0]['pinned'])
        self.assertEqual(len(self.store.history('chat')['messages']),1)

    def test_optimistic_memory_preserves_source(self):
        payload=dict(content='Prefer concise',evidence='Explicit request',kind='preference',source_session='chat',created_at=10)
        self.store.remember('m',payload)
        self.store.update_memory('m',{**payload,'content':'Prefer detail'},0)
        row=self.store.memory_rows()[0]
        self.assertEqual((row['revision'],row['source_session'],row['created_at']),(1,'chat',10))
        with self.assertRaises(ValueError):self.store.update_memory('m',payload,0)

    def test_bounded_instructions_tasks_and_title(self):
        self.store.set_setting('user_instructions','Use short paragraphs')
        self.assertEqual(self.store.setting('user_instructions'),'Use short paragraphs')
        with self.assertRaises(ValueError):self.store.set_setting('user_instructions','界'*3000)
        with self.assertRaises(ValueError):self.store.set_tasks('chat',[{'title':'x','status':'approved'}])
        tasks=[{'title':'Observe pressure','status':'running'}]
        self.assertEqual(self.store.set_tasks('chat',tasks),tasks)
        self.assertEqual(self.store.tasks('chat'),tasks)
        self.assertTrue(self.store.set_generated_title('chat','Memory pressure investigation',0))
        self.assertFalse(self.store.set_generated_title('chat','Repeat',1))

    def test_old_task_writer_cannot_overwrite_new_run(self):
        self.store.checkpoint('chat',[],[],'new','running')
        with self.assertRaises(ValueError):self.store.set_tasks('chat',[{'title':'Old run','status':'completed'}],'run')
        self.store.set_tasks('chat',[{'title':'New run','status':'running'}],'new')
        self.assertEqual(self.store.tasks('chat')[0]['title'],'New run')

    def test_second_opinion_is_tool_free_bounded_and_billed(self):
        import asyncio
        from unittest.mock import patch
        from assistant_utilities import AssistantUtilities
        from providers import ProviderConfiguration
        from coworker.providers.base import AssistantTurn, TokenUsage
        calls=[]
        class Analyst:
            def complete(self,**kwargs):
                calls.append(kwargs)
                return AssistantTurn(text='Evidence supports memory pressure; not a hardware diagnosis.',usage=TokenUsage(input=20,output=10))
        config=ProviderConfiguration(memory_enabled=False)
        utility=AssistantUtilities(self.store,config,'chat','run')
        with patch.object(ProviderConfiguration,'make_provider',return_value=Analyst()):
            result=asyncio.run(utility.request_second_opinion('Check this finding','Pressure remained elevated for 30 seconds.'))
        self.assertIn('review',result)
        self.assertNotIn('tools',calls[0])
        self.assertIn('No tools',calls[0]['messages'][0]['content'])
        again=asyncio.run(utility.request_second_opinion('Again','Evidence'))
        self.assertIn('error',again)
        usage=self.store.usage('chat')
        self.assertEqual(usage['totals']['totalTokens'],30)
        self.assertIsNone(usage['context'])

    def test_undo_memory_save_never_deletes_an_edit(self):
        payload=dict(content='Short answers',evidence='User request',kind='preference')
        self.store.remember('m',payload)
        self.store.update_memory('m',{**payload,'content':'Long answers'},0)
        self.assertFalse(self.store.undo_memory_save('m',0))
        self.assertEqual(self.store.memory_rows()[0]['content'],'Long answers')
        self.assertTrue(self.store.undo_memory_save('m',1))

    def test_entry_point_registers_every_route_before_serving(self):
        import ast
        nodes=ast.parse(Path(__file__).with_name('server.py').read_text()).body
        entry=next(i for i,n in enumerate(nodes) if isinstance(n,ast.If) and '__name__' in ast.unparse(n.test))
        routes=[i for i,n in enumerate(nodes) if isinstance(n,ast.AsyncFunctionDef) and n.decorator_list]
        self.assertTrue(routes and max(routes)<entry)

if __name__=='__main__':unittest.main()

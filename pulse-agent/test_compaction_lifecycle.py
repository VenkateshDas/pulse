"""Compaction uses real upstream policy with bounded, interruptible transport."""
import asyncio
import tempfile
import threading
import unittest
import uuid
from unittest.mock import patch
from coworker.providers.base import AssistantTurn
from conversation_store import ConversationStore
from openworker_runtime import PulseTurnEngine, _CompactionProvider, estimate
from providers import ProviderConfiguration

class SummaryProvider:
    def __init__(self, blocked=False):
        self.started = threading.Event()
        self.release = threading.Event()
        if not blocked:
            self.release.set()
        self.calls = []
    def complete(self, **kwargs):
        self.calls.append(kwargs)
        self.started.set()
        self.release.wait(5)
        return AssistantTurn(text='\n'.join(f'## {heading}\nKeep the original user request, verified evidence and unresolved work. Earlier canonical messages remain searchable.' for heading in
            ['Primary request', 'Key concepts', 'Artifacts and files', 'Errors and fixes', 'User messages', 'Pending tasks', 'Current work', 'Next step']))

class CompactionLifecycleTests(unittest.IsolatedAsyncioTestCase):
    def engine(self, directory, provider, count=40):
        config = ProviderConfiguration(context_tokens=16384, output_tokens=2048, memory_enabled=False)
        store = ConversationStore(directory + '/state.db')
        sid = str(uuid.uuid4())
        history = []
        for i in range(count):
            history.extend([{'role': 'user', 'content': f'Question {i}: ' + 'context '*25},
                            {'role': 'assistant', 'content': f'Answer {i}: ' + 'evidence '*25}])
        store.checkpoint(sid, history, history, 'seed', 'completed')
        return PulseTurnEngine(configuration=config, store=store, session_id=sid,
                               run_id=str(uuid.uuid4()), provider=provider)

    async def assert_slot_released(self, slots):
        for _ in range(100):
            if slots.acquire(blocking=False):
                slots.release()
                return
            await asyncio.sleep(.01)
        self.fail('Summary worker did not release capacity after exiting')

    async def test_stop_returns_promptly_but_blocked_worker_keeps_capacity(self):
        with tempfile.TemporaryDirectory() as directory:
            slots = threading.BoundedSemaphore(1)
            provider = SummaryProvider(blocked=True)
            with patch('openworker_runtime.PRODUCERS', slots):
                engine = self.engine(directory, provider)
                task = asyncio.create_task(engine._compact_now(force=True))
                try:
                    self.assertTrue(await asyncio.to_thread(provider.started.wait, 2))
                    engine.request_interrupt()
                    self.assertIsNone(await asyncio.wait_for(task, .5))
                    self.assertFalse(slots.acquire(blocking=False))
                    self.assertIsNone(engine.compaction_state)
                finally:
                    provider.release.set()
                    if not task.done():
                        task.cancel()
                        await asyncio.gather(task, return_exceptions=True)
                    await self.assert_slot_released(slots)

    async def test_deadline_does_not_release_blocked_worker_or_publish_late_state(self):
        with tempfile.TemporaryDirectory() as directory:
            slots = threading.BoundedSemaphore(1)
            provider = SummaryProvider(blocked=True)
            with patch('openworker_runtime.PRODUCERS', slots), patch('openworker_runtime.COMPACTION_TIMEOUT', .05):
                engine = self.engine(directory, provider)
                try:
                    with self.assertRaises(TimeoutError):
                        await engine._compact_now(force=True)
                    self.assertTrue(provider.started.is_set())
                    self.assertFalse(slots.acquire(blocking=False))
                    self.assertIsNone(engine.compaction_state)
                finally:
                    provider.release.set()
                    await self.assert_slot_released(slots)
                await asyncio.sleep(0)
                self.assertIsNone(engine.compaction_state)

    async def test_summary_input_output_budget_and_shared_capacity(self):
        config = ProviderConfiguration(context_tokens=8192, output_tokens=1024)
        provider = SummaryProvider()
        transport = _CompactionProvider(provider, config, asyncio.Event())
        slots = threading.BoundedSemaphore(1)
        with patch('openworker_runtime.PRODUCERS', slots):
            with self.assertRaises(ValueError):
                transport.complete(model='fixture', messages=[{'role':'user', 'content':'x'*30000}], max_tokens=1024)
            self.assertEqual([], provider.calls)
            self.assertTrue(slots.acquire(blocking=False))
            with self.assertRaises(RuntimeError):
                transport.complete(model='fixture', messages=[], max_tokens=1024)
            slots.release()
            transport.complete(model='fixture', messages=[], max_tokens=999999)
            self.assertEqual(1024, provider.calls[0]['max_tokens'])

    async def test_oversized_import_uses_honest_upstream_trim_without_overbudget_summary(self):
        with tempfile.TemporaryDirectory() as directory:
            provider = SummaryProvider()
            engine = self.engine(directory, provider, count=300)
            notice = await engine._compact_now(force=True)
            self.assertIn('trimmed', notice.lower())
            self.assertTrue(engine.compaction_state.trimmed)
            self.assertEqual([], provider.calls)
            self.assertLessEqual(estimate(engine._outbound_messages(), engine.registry.schemas()),
                                 engine.configuration.context_tokens-engine.configuration.output_tokens)
            self.assertEqual(50, len(engine.store.history(engine.session_id)['messages']))
            self.assertIn('Question 0', engine.store.search(engine.session_id, 'Question 0')['matches'][0]['text'])

    async def test_interaction_expiry_clears_pending_gate(self):
        from coworker.providers.base import ToolCall
        with tempfile.TemporaryDirectory() as directory, patch('openworker_runtime.INTERACTION_TIMEOUT', .02):
            engine = self.engine(directory, SummaryProvider(), count=0)
            async def consume():
                return [event async for event in engine._handle_tool_calls(
                    [ToolCall('call', 'set_keep_awake', {'until_seconds':60})])]
            with self.assertRaises(TimeoutError):
                await asyncio.wait_for(consume(), 1)
            self.assertIsNone(engine.pending)
            self.assertIsNone(engine.decision)
            with engine.store.connection() as db:
                self.assertEqual('denied', db.execute('SELECT status FROM decisions').fetchone()[0])

    async def test_reasoning_chunks_are_dropped_and_final_payload_is_bounded(self):
        from coworker.providers.base import StreamChunk, ToolCall
        class ChunkProvider(SummaryProvider):
            def __init__(self, chunks):
                super().__init__()
                self.chunks=chunks
            def stream(self, **kwargs):
                yield from self.chunks
        with tempfile.TemporaryDirectory() as directory:
            provider=ChunkProvider([StreamChunk(reasoning_delta='private'*1000) for _ in range(20)]+
                                   [StreamChunk(turn=AssistantTurn(text='Bounded answer', reasoning='private'))])
            engine=self.engine(directory, provider, count=0)
            chunks=[chunk async for chunk in engine._astream()]
            self.assertEqual(1,len(chunks))
            self.assertIsNone(chunks[0].turn.reasoning)
            for turn in [AssistantTurn(text='x'*128001),
                         AssistantTurn(tool_calls=[ToolCall('call','ask_user',{'question':'x'*128001})])]:
                with self.subTest(kind='text' if turn.text else 'tool'):
                    engine=self.engine(directory, ChunkProvider([StreamChunk(turn=turn)]), count=0)
                    with self.assertRaises(ValueError):
                        _=[chunk async for chunk in engine._astream()]

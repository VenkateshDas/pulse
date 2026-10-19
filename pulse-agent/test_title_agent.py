import asyncio
import copy
import threading
import unittest
from types import SimpleNamespace
from unittest.mock import patch
import title_agent


class Store:
    def __init__(self):
        self.meta = {'title': 'Fallback', 'revision': 1, 'origin': 'provisional'}
        self.evidence = [{'role': 'user', 'content': 'Diagnose high memory usage'}, {'role': 'assistant', 'content': 'Reviewing pressure.'}]
        self.commits = []
    def session_metadata(self, session): return dict(self.meta) if self.meta else None
    def title_evidence(self, session): return self.evidence
    def set_generated_title(self, session, title, revision):
        if not self.meta or self.meta['revision'] != revision or self.meta['origin'] == 'manual': return False
        self.meta.update(title=title, revision=revision + 1, origin='generated')
        self.commits.append(title)
        return True


class Meter:
    calls = []
    def __init__(self, *args): pass
    def begin(self, messages, tools, purpose, output_limit):
        self.calls.append((purpose, output_limit, tools)); return 'usage-id'
    def normalized(self, identifier, turn): pass


class Provider:
    def __init__(self, text='Memory investigation', blocked=False):
        self.text = text; self.calls = []; self.started = threading.Event(); self.release = threading.Event()
        self.closed = False; self._client = SimpleNamespace(close=lambda: setattr(self, 'closed', True))
        if not blocked: self.release.set()
    def complete(self, **kwargs):
        self.calls.append(kwargs); self.started.set(); self.release.wait(3)
        if isinstance(self.text, Exception): raise self.text
        return SimpleNamespace(text=self.text)


class Config:
    model = 'fixture-model'
    def __init__(self, provider): self.provider = provider
    def model_copy(self, deep):
        snapshot = copy.copy(self); snapshot.model = self.model; return snapshot
    def make_provider(self, request_meter): return self.provider


class TitleAgentTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.meter_patch = patch('title_agent.UsageMeter', Meter); self.meter_patch.start()
        Meter.calls = []
    def tearDown(self): self.meter_patch.stop()

    async def test_detached_tool_free_billed_snapshot_and_closed_client(self):
        jobs, store, provider = title_agent.TitleAgentJobs(), Store(), Provider(blocked=True)
        config = Config(provider)
        jobs.start(store, config, 'session'); config.model = 'changed-model'
        self.assertIsInstance(jobs.jobs['session'], asyncio.Task)
        self.assertEqual([], store.commits)
        try:
            self.assertTrue(await asyncio.to_thread(provider.started.wait, 1))
        finally: provider.release.set()
        await jobs.wait('session')
        self.assertEqual(['Memory investigation'], store.commits)
        self.assertEqual('fixture-model', provider.calls[0]['model'])
        self.assertEqual([], provider.calls[0]['tools'])
        self.assertEqual(128, provider.calls[0]['max_tokens'])
        self.assertEqual('none', provider.calls[0]['reasoning_effort'])
        self.assertEqual([('title', 128, [])], Meter.calls)
        self.assertTrue(provider.closed)

    async def test_manual_rename_wins_optimistic_race(self):
        jobs, store, provider = title_agent.TitleAgentJobs(), Store(), Provider(blocked=True)
        jobs.start(store, Config(provider), 'session')
        try:
            self.assertTrue(await asyncio.to_thread(provider.started.wait, 1))
            store.meta.update(title='My title', revision=2, origin='manual')
        finally: provider.release.set()
        await jobs.wait('session')
        self.assertEqual('My title', store.meta['title']); self.assertEqual([], store.commits)
        jobs.start(store, Config(provider), 'session')
        self.assertNotIn('session', jobs.jobs)

    async def test_failure_and_invalid_titles_preserve_fallback(self):
        for text in ['', ' ' * 5, 'x' * 81, None, RuntimeError('private provider error')]:
            with self.subTest(text=type(text).__name__):
                jobs, store, provider = title_agent.TitleAgentJobs(), Store(), Provider(text)
                jobs.start(store, Config(provider), 'session'); await jobs.wait('session')
                self.assertEqual([], store.commits); self.assertTrue(provider.closed)
        self.assertEqual('Memory pressure', title_agent.clean_title('  “Memory\n pressure”  '))
        self.assertEqual(60, len(title_agent.clean_title('x' * 75)))

    async def test_greeting_retry_is_bounded(self):
        jobs, store, provider = title_agent.TitleAgentJobs(), Store(), Provider()
        store.evidence = [{'role': 'user', 'content': 'Hello!'}]
        for _ in range(3):
            jobs.start(store, Config(provider), 'session'); await jobs.wait('session'); await asyncio.sleep(0)
        self.assertEqual(2, jobs.attempts['session']); self.assertEqual([], provider.calls)

    async def test_timeout_retains_worker_capacity_and_cannot_commit_late(self):
        jobs, store, provider = title_agent.TitleAgentJobs(), Store(), Provider(blocked=True)
        slots = threading.BoundedSemaphore(1)
        with patch('title_agent.PRODUCERS', slots), patch('title_agent.TITLE_TIMEOUT', .02):
            jobs.start(store, Config(provider), 'session')
            try:
                self.assertTrue(await asyncio.to_thread(provider.started.wait, 1))
                await jobs.wait('session')
                self.assertFalse(slots.acquire(blocking=False)); self.assertEqual([], store.commits)
            finally: provider.release.set()
            for _ in range(100):
                if slots.acquire(blocking=False): slots.release(); break
                await asyncio.sleep(.01)
            else: self.fail('Worker capacity did not release')
        self.assertTrue(provider.closed); self.assertEqual([], store.commits)

    async def test_shutdown_cannot_commit_late(self):
        jobs, store, provider = title_agent.TitleAgentJobs(), Store(), Provider(blocked=True)
        jobs.start(store, Config(provider), 'session')
        try:
            self.assertTrue(await asyncio.to_thread(provider.started.wait, 1))
            await jobs.stop()
            self.assertEqual({}, jobs.jobs)
        finally: provider.release.set()
        await asyncio.sleep(.03)
        self.assertEqual([], store.commits)


if __name__ == '__main__': unittest.main()

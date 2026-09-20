import json
import tempfile
import unittest

from agno.run.agent import RunOutput, RunPausedEvent

import server
from agent import create_pulse_agent


class PauseResumeTests(unittest.IsolatedAsyncioTestCase):
    async def test_pause_retains_resumable_run_output(self):
        async def stream():
            yield RunPausedEvent()
            yield RunOutput(run_id="agno-run", session_id="session")

        server.paused_runs.clear()
        lines = [line async for line in server.translate(stream(), "pulse-run", "session", [])]
        kinds = [json.loads(line.split("data: ", 1)[1])["kind"] for line in lines]

        self.assertEqual(["approval.requested", "run.paused"], kinds)
        self.assertIsInstance(server.paused_runs["pulse-run"], RunOutput)

    async def test_continue_uses_stored_run_output(self):
        class FakeAgent:
            def acontinue_run(self, *, run_response, **_):
                assert isinstance(run_response, RunOutput)

                async def stream():
                    yield RunOutput(run_id="agno-run", session_id="session", content="Done")

                return stream()

        previous = server.agent_instance
        server.agent_instance = FakeAgent()
        server.paused_runs["pulse-run"] = RunOutput(run_id="agno-run", session_id="session")
        server.run_events["pulse-run"] = [{"session_id": "session"}]
        try:
            response = await server.continue_run("pulse-run", server.ContinueRequest(approved=True))
            lines = [line async for line in response.body_iterator]
        finally:
            server.agent_instance = previous
            server.paused_runs.clear()
            server.run_events.clear()

        kinds = [json.loads(line.split("data: ", 1)[1])["kind"] for line in lines]
        self.assertEqual(["approval.resolved", "run.continued", "answer.final", "run.completed"], kinds)


class ContextBoundsTests(unittest.IsolatedAsyncioTestCase):
    def test_agent_uses_summary_and_lazy_history_not_eager_runs(self):
        with tempfile.TemporaryDirectory() as directory:
            agent = create_pulse_agent(db_path=f"{directory}/agent.db")

        self.assertFalse(agent.add_history_to_context)
        self.assertTrue(agent.read_chat_history)
        self.assertEqual(0, agent.max_tool_calls_from_history)
        self.assertEqual(1, agent.session_summary_manager.last_n_runs)

    def test_history_page_uses_latest_snapshot_and_is_bounded(self):
        messages = [
            {"role": "user", "content": f"question-{index}"}
            for index in range(30)
        ] + [{"role": "assistant", "content": "x" * 50_000}]

        page = server.history_page(messages, offset=0, limit=24)

        self.assertEqual(24, len(page["messages"]))
        self.assertEqual(24, page["next_offset"])
        self.assertLessEqual(len(page["messages"][-1]["content"]), 12_000)

        earlier = server.history_page(messages, offset=page["next_offset"], limit=24)
        self.assertEqual(7, len(earlier["messages"]))
        self.assertIsNone(earlier["next_offset"])

    async def test_replay_buffer_drops_old_large_events_but_keeps_sequences(self):
        run_id, store = "bounded-run", []
        server.run_sequences.pop(run_id, None)
        for _ in range(server.MAX_REPLAY_EVENTS + 12):
            async for _ in server.emit(store, run_id, "session", "answer.delta", {"text": "x" * 800}):
                pass

        self.assertEqual(server.MAX_REPLAY_EVENTS, len(store))
        self.assertEqual(13, store[0]["sequence"])
        self.assertEqual(server.MAX_REPLAY_EVENTS + 12, store[-1]["sequence"])

    async def test_live_final_answer_is_not_kept_unbounded_for_replay(self):
        run_id, store = "final-run", []
        server.run_sequences.pop(run_id, None)
        lines = [line async for line in server.emit(store, run_id, "session", "answer.final", {"text": "x" * 50_000})]

        sent = json.loads(lines[0].split("data: ", 1)[1])
        self.assertEqual(50_000, len(sent["payload"]["text"]))
        self.assertLessEqual(len(store[0]["payload"]["text"]), 800)

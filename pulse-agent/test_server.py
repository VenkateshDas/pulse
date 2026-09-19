import json
import unittest

from agno.run.agent import RunOutput, RunPausedEvent

import server


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

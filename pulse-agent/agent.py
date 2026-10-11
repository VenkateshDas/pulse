"""Isolated Agno run, bounded context, composed learning and progressive skills."""
from pathlib import Path
import os, json
from agno.agent import Agent
from agno.learn import LearningMachine
from agno.offload import ResultStore
from agno.skills import LocalSkills, Skills
from agno.session import SessionSummaryManager
from context import build_system_instructions
from pulse_toolkit import PulseToolkit
from memory import PulseMemoryStore
from storage import USER_ID, database
from providers import ProviderConfiguration
from budget import bound_model

class ReadOnlySkills(Skills):
    def get_tools(self):
        return [t for t in super().get_tools() if t.name != "get_skill_script"]

class CheckpointSummary(SessionSummaryManager):
    """Generate only every four turns, keeping summary calls off ordinary turns."""
    async def acreate_session_summary(self, session, *args, **kwargs):
        if len(session.runs or []) % 4: return session.summary
        return await super().acreate_session_summary(session, *args, **kwargs)


def create_pulse_agent(session_id=None, run_id=None, db_path=None, model=None, configuration=None, context=None):
    config = configuration or ProviderConfiguration.from_environment()
    active_model = bound_model(model or config.make_model(), config.context_tokens, config.output_tokens)
    db = database() if db_path is None else __import__('agno.db.sqlite', fromlist=['SqliteDb']).SqliteDb(db_file=db_path)
    root = Path(__file__).resolve().parent.parent
    directory = Path(os.environ.get("PULSE_SKILL_DIR") or root / ".agents/skills/pulse")
    if not (directory / "SKILL.md").is_file(): raise RuntimeError("Bundled Pulse skill missing")
    skills = ReadOnlySkills(loaders=[LocalSkills(str(directory))])
    if not skills._skills: raise RuntimeError("Pulse skill could not be loaded")
    # Replay dialogue, not old tool payloads. Large skill/native results must
    # not erase conversation history. Results remain persisted. Reserve room
    # for skills/tool schemas, memory, current request and requested output.
    history_runs = 4
    from agno.db.base import SessionType
    session = db.get_session(session_id, session_type=SessionType.AGENT, runs_limit=4) if session_id else None
    if session:
        available_chars = max(0, (config.context_tokens - config.output_tokens - 12000))
        consumed = 0; history_runs = 0
        for run in reversed(session.runs or []):
            size = sum(len(str(m.content or '')) for m in run.messages or [] if not m.from_history and m.role in {'user', 'assistant'})
            if consumed + size > available_chars: break
            consumed += size; history_runs += 1
    return Agent(id="pulse-agent", name="Ask Pulse", model=active_model, db=db,
        user_id=USER_ID, session_id=session_id, tools=[PulseToolkit(run_id=run_id, session_id=session_id)],
        skills=skills, instructions=build_system_instructions(), additional_context=context, telemetry=False,
        tool_call_limit=16, add_history_to_context=history_runs > 0, num_history_runs=history_runs,
        max_tool_calls_from_history=0, store_history_messages=False,
        offload_tool_results=ResultStore(db=db, threshold_chars=6000, preview_chars=1000, preview_lines=12, ttl_seconds=7*86400),
        learning=LearningMachine(custom_stores={"pulse": PulseMemoryStore(session_id, config.memory_enabled)}, namespace=USER_ID),
        enable_session_summaries=True, add_session_summary_to_context=True,
        session_summary_manager=CheckpointSummary(model=active_model, last_n_runs=4,
            session_summary_prompt="Summarize verified findings, user decisions and unresolved work in at most 200 words. Exclude secrets, raw paths, raw tool output, approvals and provider reasoning. Never invent outcomes."),
        markdown=True)

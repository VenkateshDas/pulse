"""
Pulse Agent Core Definition using Agno 3.0+.
Combines LocalSkills, PulseToolkit, SQLite session persistence,
and Context Compression for robust macOS administration.
"""

import os
from pathlib import Path
from typing import Optional

from agno.agent import Agent
from agno.compression.manager import CompressionManager
from agno.db.sqlite import SqliteDb
from agno.models.openai import OpenAIChat
from agno.session import SessionSummaryManager
from agno.skills import LocalSkills, Skills

from context import build_system_instructions
from pulse_toolkit import PulseToolkit


def get_default_model():
    """Resolve model from environment variables or sensible default."""
    if os.environ.get("ANTHROPIC_API_KEY"):
        try:
            from agno.models.anthropic import Claude
            return Claude(id="claude-3-7-sonnet-20250219")
        except Exception:
            pass

    # Support custom / local OpenAI-compatible endpoints (Ollama, vLLM, LMStudio)
    base_url = os.environ.get("OPENAI_BASE_URL")
    model_id = os.environ.get("PULSE_MODEL_ID", "gpt-4o")
    api_key = os.environ.get("OPENAI_API_KEY", "dummy_key_if_unconfigured")

    return OpenAIChat(
        id=model_id,
        base_url=base_url,
        api_key=api_key,
    )


def create_pulse_agent(
    session_id: Optional[str] = None,
    db_path: Optional[str] = None,
    model=None,
) -> Agent:
    """Instantiate a fully configured Pulse Agno Agent."""
    repo_root = Path(__file__).resolve().parent.parent
    pulse_skill_dir = Path(os.environ.get("PULSE_SKILL_DIR", repo_root / ".agents" / "skills" / "pulse"))

    # Ensure database path
    if db_path is None:
        pulse_dir = Path.home() / ".pulse"
        pulse_dir.mkdir(parents=True, exist_ok=True)
        db_path = str(pulse_dir / "agent.db")
    else:
        Path(db_path).parent.mkdir(parents=True, exist_ok=True)

    db = SqliteDb(db_file=db_path)

    # Context compression manager
    compression_manager = CompressionManager(
        compress_tool_results=True,
        compress_token_limit=4000,
        compress_tool_results_limit=3,
    )

    # Load Pulse Skill
    skills = None
    if pulse_skill_dir.exists():
        skills = Skills(loaders=[LocalSkills(str(pulse_skill_dir))])

    # Toolkits
    pulse_toolkit = PulseToolkit()

    active_model = model or get_default_model()

    agent = Agent(
        id="pulse-agent",
        name="Pulse AI",
        model=active_model,
        db=db,
        session_id=session_id,
        tools=[pulse_toolkit],
        skills=skills,
        instructions=build_system_instructions(),
        compression_manager=compression_manager,
        # Never inject previous runs wholesale. Agno persists each run with
        # its message list, so one large answer would otherwise be sent again
        # on every follow-up. The summary carries normal continuity; the
        # history tool loads old detail only when the current question needs it.
        add_history_to_context=False,
        read_chat_history=True,
        max_tool_calls_from_history=0,
        enable_session_summaries=True,
        add_session_summary_to_context=True,
        session_summary_manager=SessionSummaryManager(
            model=active_model,
            # Agno persists a cumulative message snapshot per run. Summarizing
            # ten snapshots is therefore quadratic after a long first answer.
            # One newest snapshot updates the existing durable summary.
            last_n_runs=1,
            session_summary_prompt=(
                "Summarize only verified findings, user decisions, pending "
                "approvals, and unresolved work. Never include secrets, raw "
                "paths, full tool output, or provider reasoning."
            ),
        ),
        markdown=True,
    )

    return agent


if __name__ == "__main__":
    print("Initializing Pulse Agent...")
    agent = create_pulse_agent()
    print(f"Agent '{agent.name}' ready with {len(agent.tools)} tools.")

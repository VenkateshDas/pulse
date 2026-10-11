"""Application Support storage using Agno APIs, never private SQL table layouts."""
import os, sqlite3, uuid
from pathlib import Path
from agno.db.sqlite import SqliteDb
from agno.db.base import SessionType

RUNTIME_DIR = Path(os.getenv("PULSE_AGENT_RUNTIME_DIR", Path.home() / "Library/Application Support/Pulse/agent"))
RUNTIME_DIR.mkdir(parents=True, exist_ok=True)
os.chmod(RUNTIME_DIR, 0o700)
DB_PATH = RUNTIME_DIR / "agent.db"
legacy = Path.home() / ".pulse/agent.db"
if not DB_PATH.exists() and legacy.exists():
    # SQLite backup includes WAL data and leaves the original untouched.
    with sqlite3.connect(legacy) as source, sqlite3.connect(DB_PATH) as destination:
        source.backup(destination)
identity_path = RUNTIME_DIR / "user-id"
if not identity_path.exists(): identity_path.write_text(str(uuid.uuid4()))
os.chmod(identity_path, 0o600)
USER_ID = identity_path.read_text().strip()

def database():
    return SqliteDb(db_file=str(DB_PATH))

def session_page(page=1):
    sessions = database().get_sessions(session_type=SessionType.AGENT, component_id="pulse-agent", limit=50, page=page, include_runs=False)
    return [{"session_id": s.session_id, "name": (s.session_data or {}).get("session_name", "Conversation"),
             "created_at": s.created_at, "updated_at": s.updated_at} for s in sessions]

def history_page(session_id, page=1):
    session = database().get_session(session_id, session_type=SessionType.AGENT, runs_limit=min(500, page * 50 + 1))
    if not session: return {"messages": [], "has_more": False}
    # get_messages excludes from_history copies and private/system/tool messages.
    messages = [m for m in session.get_messages(skip_roles=["system", "tool"]) if m.role in {"user", "assistant"} and isinstance(m.content, str) and m.content and not m.tool_calls]
    end = max(0, len(messages) - (page - 1) * 50)
    start = max(0, end - 50)
    return {"messages": [{"role": m.role, "content": m.content[:64000]} for m in messages[start:end]], "has_more": start > 0}

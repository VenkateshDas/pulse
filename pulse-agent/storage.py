"""Application Support storage using Agno APIs, never private SQL table layouts."""
import os, sqlite3, uuid
from pathlib import Path

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
    from agno.db.sqlite import SqliteDb
    return SqliteDb(db_file=str(DB_PATH))

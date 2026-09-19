"""Authenticated local Agno runtime with Pulse-owned SSE events."""
import json, os, sqlite3, uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, AsyncIterator, Dict, Optional

from fastapi import Depends, FastAPI, Header, HTTPException
from fastapi.responses import StreamingResponse
from agno.run.agent import RunOutput
from pydantic import BaseModel
from agent import create_pulse_agent

app = FastAPI(title="Pulse Agent", version="1")
TOKEN = os.environ.get("PULSE_AGENT_TOKEN")
agent_instance = None
paused_runs: Dict[str, Any] = {}
run_events: Dict[str, list[dict[str, Any]]] = {}

def require_token(authorization: Optional[str] = Header(default=None)) -> None:
    if not TOKEN or authorization != f"Bearer {TOKEN}":
        raise HTTPException(status_code=401, detail="Pulse Agent token required")

def agent():
    global agent_instance
    if agent_instance is None: agent_instance = create_pulse_agent()
    return agent_instance

class RunRequest(BaseModel):
    message: str
    session_id: Optional[str] = None
class ContinueRequest(BaseModel):
    approved: bool
class ConfigurationRequest(BaseModel):
    base_url: str
    api_key: str
    model: str

def compact(value: Any, limit: Optional[int] = 800) -> str:
    text = value if isinstance(value, str) else json.dumps(value, default=str, separators=(",", ":"))
    return text if limit is None or len(text) <= limit else text[: limit - 1] + "…"

def title_for(name: str) -> str:
    return {"diagnose": "Checking system health", "get_vitals": "Reading system vitals", "get_top_processes": "Checking highest CPU users", "inspect_storage_growth": "Checking storage growth", "scan_clean_targets": "Finding cleanup candidates", "clean_target": "Previewing cleanup", "uninstall_app": "Previewing app removal", "find_duplicates": "Finding exact duplicates"}.get(name, name.replace("_", " ").capitalize())

def make_event(sequence: int, run_id: str, session_id: str, kind: str, payload: Optional[Dict[str, Any]] = None) -> dict[str, Any]:
    limit = None if kind == "answer.final" else 800
    return {"version": 1, "event_id": str(uuid.uuid4()), "sequence": sequence, "run_id": run_id, "session_id": session_id, "timestamp": datetime.now(timezone.utc).isoformat(), "kind": kind, "payload": {key: compact(value, limit) for key, value in (payload or {}).items() if value is not None}}

async def emit(store: list[dict[str, Any]], run_id: str, session_id: str, kind: str, payload: Optional[Dict[str, Any]] = None) -> AsyncIterator[str]:
    event = make_event(len(store) + 1, run_id, session_id, kind, payload)
    store.append(event)
    yield f"event: pulse\ndata: {json.dumps(event)}\n\n"

async def translate(stream: Any, run_id: str, session_id: str, store: list[dict[str, Any]]) -> AsyncIterator[str]:
    """Expose observed progress only. Never forward private provider reasoning."""
    answer = ""
    final_answer = ""
    pause_event = None
    async for item in stream:
        event_name = str(getattr(item, "event", "")).lower()
        tool = getattr(item, "tool", None) or getattr(item, "tool_execution", None)
        if tool and "started" in event_name:
            name = getattr(tool, "tool_name", "tool")
            async for line in emit(store, run_id, session_id, "tool.started", {"tool_call_id": getattr(tool, "tool_call_id", None) or str(uuid.uuid4()), "title": title_for(name), "detail": getattr(tool, "tool_args", {})}): yield line
        elif tool and ("completed" in event_name or "error" in event_name):
            name = getattr(tool, "tool_name", "tool")
            kind = "tool.failed" if "error" in event_name else "tool.completed"
            async for line in emit(store, run_id, session_id, kind, {"tool_call_id": getattr(tool, "tool_call_id", None) or str(uuid.uuid4()), "title": title_for(name), "detail": getattr(tool, "result", getattr(tool, "content", "Complete"))}): yield line
        content = getattr(item, "content", None)
        if event_name == "runcontent" and isinstance(content, str) and content:
            answer += content
            async for line in emit(store, run_id, session_id, "answer.delta", {"text": content}): yield line
        elif event_name == "runcompleted" and isinstance(content, str) and content:
            final_answer = content
        if getattr(item, "is_paused", False):
            # Agno emits RunPausedEvent first, then RunOutput only when
            # yield_run_output=True. The event is notification data, not a
            # resumable run; retaining it makes acontinue_run crash.
            pause_event = item
            continue
        if pause_event is not None and isinstance(item, RunOutput):
            paused_runs[run_id] = item
            requirements = getattr(pause_event, "active_requirements", [])
            pending = getattr(requirements[0], "tool_execution", None) if requirements else None
            async for line in emit(store, run_id, session_id, "approval.requested", {"title": title_for(getattr(pending, "tool_name", "action")), "detail": "Review exact affected items before approving this action."}): yield line
            async for line in emit(store, run_id, session_id, "run.paused"): yield line
            return
    async for line in emit(store, run_id, session_id, "answer.final", {"text": final_answer or answer}): yield line
    async for line in emit(store, run_id, session_id, "run.completed"): yield line

@app.get("/status", dependencies=[Depends(require_token)])
async def status() -> dict[str, Any]:
    return {"status": "ok", "has_api_key": bool(os.environ.get("OPENAI_API_KEY") or os.environ.get("ANTHROPIC_API_KEY")), "summary": "Ready"}

@app.post("/config", dependencies=[Depends(require_token)])
async def configure(request: ConfigurationRequest) -> dict[str, str]:
    """Apply new provider settings only after native Keychain persistence."""
    global agent_instance
    os.environ["OPENAI_BASE_URL"] = request.base_url.strip()
    os.environ["OPENAI_API_KEY"] = request.api_key
    os.environ["PULSE_MODEL_ID"] = request.model.strip()
    agent_instance = None
    return {"status": "updated"}

@app.post("/runs", dependencies=[Depends(require_token)])
async def run(request: RunRequest) -> StreamingResponse:
    async def events() -> AsyncIterator[str]:
        session_id, run_id = request.session_id or str(uuid.uuid4()), str(uuid.uuid4())
        store = run_events.setdefault(run_id, [])
        async for line in emit(store, run_id, session_id, "run.started"): yield line
        async for line in emit(store, run_id, session_id, "reasoning.summary.delta", {"text": "Checking current Pulse evidence."}): yield line
        if not (os.environ.get("OPENAI_API_KEY") or os.environ.get("ANTHROPIC_API_KEY")):
            async for line in emit(store, run_id, session_id, "run.failed", {"text": "Add a model key in Pulse Agent settings to continue."}): yield line
            return
        try:
            # Agno returns an async generator when streaming. Awaiting it
            # raises TypeError before any provider response can be consumed.
            stream = agent().arun(input=request.message, session_id=session_id, stream=True, stream_events=True, yield_run_output=True)
            async for line in translate(stream, run_id, session_id, store): yield line
        except Exception:
            # Provider exceptions may include endpoint or request diagnostics.
            # Keep those in local server logs; never put them in chat history.
            async for line in emit(store, run_id, session_id, "run.failed", {"text": "The provider request failed. Check Agent settings and try again."}): yield line
    return StreamingResponse(events(), media_type="text/event-stream", headers={"Cache-Control": "no-cache"})

@app.post("/runs/{run_id}/continue", dependencies=[Depends(require_token)])
async def continue_run(run_id: str, request: ContinueRequest) -> StreamingResponse:
    paused = paused_runs.get(run_id)
    async def events() -> AsyncIterator[str]:
        store = run_events.setdefault(run_id, [])
        session_id = store[0]["session_id"] if store else ""
        if paused is None:
            async for line in emit(store, run_id, session_id, "run.failed", {"text": "This approval is no longer available. Start a new request."}): yield line
            return
        for requirement in getattr(paused, "active_requirements", []): requirement.confirm() if request.approved else requirement.reject()
        async for line in emit(store, run_id, session_id, "approval.resolved", {"text": "Approved" if request.approved else "Declined"}): yield line
        async for line in emit(store, run_id, session_id, "run.continued"): yield line
        try:
            stream = agent().acontinue_run(run_response=paused, stream=True, stream_events=True, yield_run_output=True)
            async for line in translate(stream, run_id, session_id, store): yield line
        except Exception:
            async for line in emit(store, run_id, session_id, "run.failed", {"text": "The approved action could not be completed. No further changes were made."}): yield line
        finally: paused_runs.pop(run_id, None)
    return StreamingResponse(events(), media_type="text/event-stream")

@app.post("/runs/{run_id}/cancel", dependencies=[Depends(require_token)])
async def cancel(run_id: str) -> dict[str, bool]:
    paused_runs.pop(run_id, None); return {"cancelled": True}

@app.get("/runs/{run_id}/events", dependencies=[Depends(require_token)])
async def replay(run_id: str, after_sequence: int = 0) -> dict[str, Any]:
    return {"events": [event for event in run_events.get(run_id, []) if event["sequence"] > after_sequence]}

@app.get("/sessions", dependencies=[Depends(require_token)])
async def sessions() -> dict[str, Any]:
    db = Path.home() / ".pulse" / "agent.db"
    if not db.exists(): return {"sessions": []}
    try:
        with sqlite3.connect(db) as connection:
            rows = connection.execute("SELECT session_id, session_data, created_at, updated_at FROM agno_sessions ORDER BY updated_at DESC LIMIT 50").fetchall()
        sessions = []
        for session_id, session_data, created_at, updated_at in rows:
            name = session_id
            with sqlite3.connect(db) as connection:
                run = connection.execute("SELECT run_data FROM agno_runs WHERE session_id = ? ORDER BY created_at ASC LIMIT 1", (session_id,)).fetchone()
            if run:
                messages = json.loads(run[0]).get("messages", [])
                first_user = next((message.get("content") for message in messages if message.get("role") == "user" and isinstance(message.get("content"), str)), None)
                if first_user: name = compact(first_user, 48)
            sessions.append({"session_id": session_id, "name": name, "created_at": created_at, "updated_at": updated_at})
        return {"sessions": sessions}
    except (sqlite3.Error, json.JSONDecodeError): return {"sessions": []}

@app.get("/sessions/{session_id}/history", dependencies=[Depends(require_token)])
async def session_history(session_id: str) -> dict[str, Any]:
    """Return only user-visible messages; never replay system prompts or reasoning."""
    db = Path.home() / ".pulse" / "agent.db"
    if not db.exists(): return {"messages": []}
    try:
        with sqlite3.connect(db) as connection:
            rows = connection.execute("SELECT run_data FROM agno_runs WHERE session_id = ? ORDER BY created_at ASC", (session_id,)).fetchall()
        messages = []
        for (raw_run,) in rows:
            for message in json.loads(raw_run).get("messages", []):
                role, content = message.get("role"), message.get("content")
                if role in {"user", "assistant"} and isinstance(content, str) and content:
                    messages.append({"role": role, "content": compact(content, 12_000)})
        return {"messages": messages}
    except (sqlite3.Error, json.JSONDecodeError): return {"messages": []}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="127.0.0.1", port=int(os.environ.get("PULSE_AGENT_PORT", "7777")), reload=False)

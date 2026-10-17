"""Authenticated, bounded local Agno harness; Pulse owns the event protocol."""
import asyncio, json, os, time, uuid
from collections import deque
from dataclasses import dataclass, field
from typing import Any, AsyncIterator, Optional
from fastapi import Depends, FastAPI, Header, HTTPException, Query
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse, StreamingResponse
from agno.run.agent import RunOutput
from pydantic import BaseModel, Field
from agent import create_pulse_agent
from providers import ProviderConfiguration
from budget import ContextBudgetExceeded
from storage import USER_ID, database, history_page, session_page
from memory import PulseMemoryStore
from pulse_toolkit import native_request

app = FastAPI(title="Pulse Agent", version="2")
TOKEN = os.getenv("PULSE_AGENT_TOKEN")
configuration = ProviderConfiguration.from_environment()
MAX_RUNS, MAX_EVENTS, RUN_TTL, MAX_ANSWER = 32, 512, 900, 128000

@dataclass
class Run:
    id: str
    session_id: str
    agent: Any
    config: ProviderConfiguration
    events: deque = field(default_factory=lambda: deque(maxlen=MAX_EVENTS))
    sequence: int = 0
    created: float = field(default_factory=time.monotonic)
    paused: Optional[RunOutput] = None
    task: Optional[asyncio.Task] = None
    cancelled: bool = False
    terminal: bool = False
    approval_id: Optional[str] = None
    decisions: dict = field(default_factory=dict)

runs: dict[str, Run] = {}
session_writers: dict[str, str] = {}

def require_token(authorization: Optional[str] = Header(default=None)):
    import secrets
    if not TOKEN or not secrets.compare_digest(authorization or "", f"Bearer {TOKEN}"):
        raise HTTPException(401, "Pulse Agent token required")

@app.exception_handler(RequestValidationError)
async def validation_error(_, __):
    # Pydantic's default response can echo rejected input, including API keys.
    return JSONResponse(status_code=422, content={"detail": "Invalid request fields or limits"})

class RunRequest(BaseModel):
    message: str = Field(min_length=1, max_length=12000)
    session_id: Optional[str] = Field(default=None, max_length=128)
class ContinueRequest(BaseModel):
    approved: bool
    approval_id: str = Field(min_length=1, max_length=128)

async def compact_json(value): return json.dumps(value, default=str, ensure_ascii=False)

def compact(value, limit=800):
    text = value if isinstance(value, str) else json.dumps(value, default=str, ensure_ascii=False)
    return text if limit is None or len(text) <= limit else text[:limit-1] + "…"

def title_for(name):
    return {"diagnose": "Checking system health", "get_vitals": "Reading system vitals", "get_top_processes": "Checking busy apps", "preview_cleanup": "Previewing cleanup", "clean_target": "Moving reviewed items to Trash", "preview_uninstall": "Previewing app removal", "uninstall_app": "Removing reviewed app", "save_pulse_memory": "Remembering useful context"}.get(name, name.replace('_', ' ').capitalize())

def prune(reserve=False):
    for key, r in list(runs.items()):
        if r.task is None and time.monotonic() - r.created > RUN_TTL:
            session_writers.pop(r.session_id, None)
            del runs[key]
    while reserve and len(runs) >= MAX_RUNS:
        victim = next((k for k, r in runs.items() if r.terminal), None)
        if victim is None: raise HTTPException(429, "Too many retained runs. Stop a run or wait for approval expiry.")
        del runs[victim]

def release(r):
    if session_writers.get(r.session_id) == r.id: session_writers.pop(r.session_id, None)
    r.paused = None; r.approval_id = None

def event_line(r, kind, payload=None):
    r.sequence += 1
    limit = None if kind in {"answer.delta", "answer.final", "approval.requested"} else 2000
    event = {"version": 1, "event_id": str(uuid.uuid4()), "sequence": r.sequence, "run_id": r.id,
             "session_id": r.session_id, "timestamp": time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
             "kind": kind, "payload": {k: compact(v, limit) for k, v in (payload or {}).items() if v is not None}}
    r.events.append(event)
    if kind in {"run.completed", "run.failed", "run.cancelled"}: r.terminal = True; release(r)
    return f"event: pulse\ndata: {json.dumps(event, ensure_ascii=False)}\n\n"

def request_approval(r):
    pending = [x for x in r.paused.active_requirements if not x.is_resolved()]
    if not pending: return None
    requirement = pending[0]
    r.approval_id = requirement.id
    tool = requirement.tool_execution
    toolkit = next((t for t in r.agent.tools if hasattr(t, "approval_evidence")), None) if hasattr(r.agent, "tools") else None
    evidence = toolkit.approval_evidence(tool.tool_name, tool.tool_args or {}) if toolkit else {"arguments": tool.tool_args or {}}
    return event_line(r, "approval.requested", {"approval_id": requirement.id,
        "title": title_for(tool.tool_name), "detail": json.dumps(evidence, ensure_ascii=False, indent=2),
        "tool_name": tool.tool_name, "preview": "Review the exact preview above. This approves only the named action and arguments."})

async def translate(stream, r):
    answer, pending, last_flush = "", "", 0.0
    pause_event = None
    async for item in stream:
        if r.cancelled: raise asyncio.CancelledError()
        name = str(getattr(item, "event", "")).lower()
        if name == "runerror": raise RuntimeError("Provider run failed")
        if name == "runcontent" and isinstance(getattr(item, "content", None), str):
            text = item.content
            answer += text; pending += text
            if len(answer) > MAX_ANSWER: raise ValueError("Answer limit")
            if time.monotonic() - last_flush >= .04:
                yield event_line(r, "answer.delta", {"text": pending})
                pending = ""; last_flush = time.monotonic()
            continue
        if pending:
            yield event_line(r, "answer.delta", {"text": pending}); pending = ""
        tool = getattr(item, "tool", None) or getattr(item, "tool_execution", None)
        if tool and "started" in name:
            yield event_line(r, "tool.started", {"tool_call_id": tool.tool_call_id, "title": title_for(tool.tool_name), "detail": tool.tool_args})
        elif tool and ("completed" in name or "error" in name):
            yield event_line(r, "tool.failed" if "error" in name else "tool.completed",
                {"tool_call_id": tool.tool_call_id, "title": title_for(tool.tool_name), "detail": getattr(tool, "result", "Complete")})
        if name == "runpaused": pause_event = item
        if isinstance(item, RunOutput):
            if pause_event is not None or item.is_paused:
                r.paused = item
                line = request_approval(r)
                if not line: raise RuntimeError("Paused without requirement")
                yield line; yield event_line(r, "run.paused"); return
            if isinstance(item.content, str): answer = item.content[:MAX_ANSWER]
        if name == "runcompleted" and isinstance(getattr(item, "content", None), str): answer = item.content[:MAX_ANSWER]
        if name == "runcancelled":
            yield event_line(r, "run.cancelled"); return
    if pause_event: raise RuntimeError("No resumable paused output")
    yield event_line(r, "answer.final", {"text": answer})
    try:
        session = await asyncio.to_thread(r.agent.db.get_session, r.session_id)
        if session and not (session.session_data or {}).get("session_name"):
            await asyncio.to_thread(r.agent.set_session_name, session_id=r.session_id, session_name=getattr(r, "message", "Conversation")[:48])
    except Exception: pass
    yield event_line(r, "run.completed")

async def serve(r, continuation=False):
    r.task = asyncio.current_task()
    try:
        if continuation:
            yield event_line(r, "run.continued")
            paused = r.paused; r.paused = None
            stream = r.agent.acontinue_run(run_response=paused, stream=True, stream_events=True, yield_run_output=True)
        else:
            yield event_line(r, "run.started", {"model": r.config.model, "provider": r.config.provider})
            stream = r.agent.arun(input=r.message, session_id=r.session_id, user_id=USER_ID, run_id=r.id,
                stream=True, stream_events=True, yield_run_output=True)
        async with asyncio.timeout(660):
            async for line in translate(stream, r): yield line
    except asyncio.CancelledError:
        r.cancelled = True
        r.agent.cancel_run(r.id)
        async def stop_native():
            try: await native_request(r.id, r.session_id, [], timeout=2, cancel=True)
            except Exception: pass
        asyncio.create_task(stop_native())
        # Record synchronously even when the socket/ASGI cancellation scope is gone.
        if not r.terminal: event_line(r, "run.cancelled", {"text": "Stop requested; an action already started may finish."})
    except ContextBudgetExceeded:
        yield event_line(r, "run.failed", {"text": "Context budget reached. Start a new conversation or choose a larger context budget."})
    except Exception as exc:
        import logging
        logging.getLogger("pulse").warning("Run failed: %s", type(exc).__name__)
        if not r.terminal: yield event_line(r, "run.failed", {"text": "Provider or native tool request failed. Check the selected transport, model, tool support and credentials, then retry."})
    finally:
        r.task = None
        if r.paused is None: release(r)

@app.get('/status', dependencies=[Depends(require_token)])
async def status():
    prune()
    return {"status": "ok", "has_api_key": configuration.ready, "summary": "Ready", "model": configuration.model,
            "provider": configuration.provider, "memory_enabled": configuration.memory_enabled,
            "active_runs": sum(not r.terminal for r in runs.values())}

@app.post('/config', dependencies=[Depends(require_token)])
async def configure(request: ProviderConfiguration):
    global configuration
    if session_writers and request.memory_enabled != configuration.memory_enabled:
        raise HTTPException(409, "Stop active runs before changing memory")
    configuration = request
    return {"status": "updated"}

@app.post('/runs', dependencies=[Depends(require_token)])
async def run(request: RunRequest):
    prune(reserve=True)
    if not configuration.ready: raise HTTPException(409, "Configure a provider or local model first")
    session_id = request.session_id or str(uuid.uuid4())
    try: uuid.UUID(session_id)
    except ValueError: raise HTTPException(422, "Invalid session ID")
    if session_id in session_writers: raise HTTPException(409, "This conversation already has an active run")
    if sum(r.task is not None or r.paused is not None for r in runs.values()) >= 4:
        raise HTTPException(429, "Too many active runs")
    run_id = str(uuid.uuid4()); config = configuration.model_copy(deep=True)
    try:
        try:
            snapshot = await native_request(run_id, session_id, ["context"], timeout=2)
            context = "Timestamped native snapshot (may be stale): " + snapshot["json"][:6000]
        except Exception:
            context = "Native snapshot unavailable. Use tools when current evidence is needed."
        instance = await asyncio.to_thread(create_pulse_agent, session_id=session_id, run_id=run_id, configuration=config, context=context)
    except Exception: raise HTTPException(503, "Agent runtime or bundled skill unavailable")
    # Agent construction may yield; check the session writer again.
    if session_id in session_writers: raise HTTPException(409, "This conversation already has an active run")
    if len(session_writers) >= 4: raise HTTPException(429, "Too many active runs")
    prune(reserve=True)
    r = Run(run_id, session_id, instance, config); r.message = request.message
    runs[run_id] = r; session_writers[session_id] = run_id
    async def expire():
        await asyncio.sleep(RUN_TTL)
        if not r.terminal:
            r.cancelled = True; r.agent.cancel_run(r.id)
            if r.task: r.task.cancel()
            event_line(r, "run.cancelled", {"text": "Run expired. Start a fresh request."})
    asyncio.create_task(expire())
    return StreamingResponse(serve(r), media_type='text/event-stream', headers={"Cache-Control": "no-cache"})

@app.post('/runs/{run_id}/continue', dependencies=[Depends(require_token)])
async def continue_run(run_id: str, request: ContinueRequest):
    r = runs.get(run_id)
    if not r or not r.paused or r.task or r.cancelled or time.monotonic()-r.created > RUN_TTL:
        raise HTTPException(409, "Approval unavailable or expired. Start a new request")
    if request.approval_id != r.approval_id or request.approval_id in r.decisions:
        raise HTTPException(409, "Approval already resolved or does not match this action")
    requirement = next((x for x in r.paused.active_requirements if x.id == request.approval_id), None)
    if not requirement: raise HTTPException(409, "Requirement unavailable")
    requirement.confirm() if request.approved else requirement.reject()
    r.decisions[request.approval_id] = request.approved
    r.approval_id = None
    async def continuation():
        yield event_line(r, "approval.resolved", {"approval_id": request.approval_id, "text": "Approved" if request.approved else "Declined"})
        # Gather one decision per requirement before resuming the batch.
        remaining = request_approval(r)
        if remaining:
            yield remaining; yield event_line(r, "run.paused"); return
        async for line in serve(r, continuation=True): yield line
    return StreamingResponse(continuation(), media_type='text/event-stream', headers={"Cache-Control": "no-cache"})

@app.post('/runs/{run_id}/cancel', dependencies=[Depends(require_token)])
async def cancel(run_id: str):
    r = runs.get(run_id)
    if not r: raise HTTPException(404, "Run unavailable")
    r.cancelled = True; r.agent.cancel_run(run_id)
    try: await native_request(r.id, r.session_id, [], timeout=2, cancel=True)
    except Exception: pass
    if r.task: r.task.cancel()
    elif not r.terminal: event_line(r, "run.cancelled")
    return {"cancelled": True}

@app.get('/runs/{run_id}/events', dependencies=[Depends(require_token)])
async def replay(run_id: str, after_sequence: int = Query(0, ge=0)):
    r = runs.get(run_id)
    if not r: raise HTTPException(404, "Replay expired")
    if r.events and after_sequence < r.events[0]['sequence'] - 1: raise HTTPException(410, "Replay gap; reload conversation history")
    return {"events": [e for e in r.events if e['sequence'] > after_sequence]}

@app.get('/sessions', dependencies=[Depends(require_token)])
async def sessions(page: int = Query(1, ge=1, le=10000)):
    try: return {"sessions": await asyncio.to_thread(session_page, page)}
    except Exception: raise HTTPException(503, "Conversation storage unavailable")

@app.get('/sessions/{session_id}/history', dependencies=[Depends(require_token)])
async def session_history(session_id: str, page: int = Query(1, ge=1, le=10000)):
    try: return await asyncio.to_thread(history_page, session_id, page)
    except Exception: raise HTTPException(503, "Conversation history unavailable")

@app.get('/memory', dependencies=[Depends(require_token)])
async def memories():
    store = PulseMemoryStore('', enabled=True)
    return {"memories": await store.arecall(), "enabled": configuration.memory_enabled}

@app.delete('/memory/{memory_id}', dependencies=[Depends(require_token)])
async def delete_memory(memory_id: str):
    if session_writers: raise HTTPException(409, "Stop active runs before changing memory")
    rows = await PulseMemoryStore('').arecall()
    if memory_id != 'all' and not any(r['id'] == memory_id for r in rows): raise HTTPException(404, "Memory unavailable")
    for row in rows:
        if memory_id == 'all' or row['id'] == memory_id: await asyncio.to_thread(database().delete_learning, row['id'])
    return {"status": "deleted"}

@app.post('/memory/toggle', dependencies=[Depends(require_token)])
async def toggle_memory(enabled: bool):
    global configuration
    if session_writers: raise HTTPException(409, "Stop active runs before changing memory")
    configuration = configuration.model_copy(update={"memory_enabled": enabled})
    return {"enabled": enabled}

if __name__ == '__main__':
    import uvicorn
    async def main():
        service = uvicorn.Server(uvicorn.Config(app, host='127.0.0.1', port=int(os.getenv('PULSE_AGENT_PORT','7777')), access_log=False))
        parent = int(os.getenv('PULSE_PARENT_PID', '0'))
        async def watch_parent():
            while not service.should_exit:
                if parent and os.getppid() != parent:
                    service.should_exit = True; return
                await asyncio.sleep(2)
        watcher = asyncio.create_task(watch_parent())
        try: await service.serve()
        finally: watcher.cancel()
    asyncio.run(main())

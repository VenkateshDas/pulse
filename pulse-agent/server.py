"""Authenticated Pulse server. OpenWorker executes; Swift owns native capabilities."""
import asyncio
from collections import deque, OrderedDict
from dataclasses import dataclass, field
import json
import os
import time
import uuid
from contextlib import asynccontextmanager
from typing import Optional, Literal
from fastapi import Depends, FastAPI, Header, HTTPException, Query
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse, StreamingResponse
from pydantic import BaseModel, Field
from coworker.events import EventType
from providers import ProviderConfiguration
from conversation_store import ConversationStore
from openworker_runtime import PulseTurnEngine
from memory import PulseMemoryStore
from title_agent import TitleAgentJobs
from pulse_toolkit import native_request
from storage import RUNTIME_DIR, database
from diagnostics import configure as configure_logs, record

TOKEN=os.getenv('PULSE_AGENT_TOKEN')
configuration=ProviderConfiguration.from_environment()
MAX_RUNS,MAX_EVENTS,RUN_TTL,MAX_ANSWER=32,512,900,128000
store=None
runs={}
session_writers={}
cancelled_requests=OrderedDict()
titles=TitleAgentJobs()

def storage():
    global store
    if store is None:
        store=ConversationStore(RUNTIME_DIR/'conversations.db')
        store.migrate(database())
        store.recover()
    return store

@asynccontextmanager
async def lifespan(app):
    configure_logs(RUNTIME_DIR)
    await asyncio.to_thread(storage)
    record('runtime.started')
    yield
    for r in list(runs.values()):
        if r.task and not r.task.done():r.task.cancel()
    await asyncio.gather(*(r.task for r in runs.values() if r.task),return_exceptions=True)
    await titles.stop()
    record('runtime.stopped')

app=FastAPI(title='Pulse OpenWorker Agent',version='3',lifespan=lifespan)

def require_token(authorization:Optional[str]=Header(default=None)):
    import secrets
    if not TOKEN or not secrets.compare_digest(authorization or '',f'Bearer {TOKEN}'):
        raise HTTPException(401,'Pulse Agent token required')

@app.exception_handler(RequestValidationError)
async def validation_error(_request,_error):
    return JSONResponse(status_code=422,content={'detail':'Invalid request fields or limits'})

class RunRequest(BaseModel):
    message:str=Field(min_length=1,max_length=12000)
    session_id:Optional[str]=Field(default=None,max_length=128)
    request_id:Optional[str]=Field(default=None,max_length=128)
    mode:Literal['investigate','interactive']='interactive'
    specialist:Literal['general','performance','storage','energy']='general'
class ContinueRequest(BaseModel):
    approved:bool=False
    approval_id:str=Field(min_length=1,max_length=128)
    answer:Optional[str]=Field(default=None,max_length=12000)

@dataclass
class Run:
    id:str
    session_id:str
    agent:PulseTurnEngine
    config:ProviderConfiguration
    events:deque=field(default_factory=lambda:deque(maxlen=MAX_EVENTS))
    sequence:int=0
    created:float=field(default_factory=time.monotonic)
    task:Optional[asyncio.Task]=None
    changed:asyncio.Event=field(default_factory=asyncio.Event)
    terminal:bool=False
    cancelled:bool=False
    approval_id:Optional[str]=None
    message:str=''
    status:str='running'


def title_for(name):
    return {'read_current_context':'Reading current evidence','observe_performance':'Observing performance',
            'preview_cleanup':'Previewing cleanup','clean_target':'Moving reviewed items to Trash',
            'preview_uninstall':'Previewing app removal','uninstall_app':'Removing reviewed app',
            'search_conversation':'Searching earlier conversation','read_tool_result':'Reading saved evidence'}.get(name,name.replace('_',' ').capitalize())

def event_line(r,kind,payload=None):
    if r.terminal:return ''
    r.sequence+=1
    fields={}
    for key,value in (payload or {}).items():
        if value is None:continue
        text=value if isinstance(value,str) else json.dumps(value,ensure_ascii=False,default=str)
        limit=MAX_ANSWER if kind.startswith('answer.') else 24000 if kind=='approval.requested' else 8000
        fields[key]=text.encode()[:limit].decode('utf-8',errors='ignore')
    event={'version':1,'event_id':str(uuid.uuid4()),'sequence':r.sequence,'run_id':r.id,'session_id':r.session_id,
           'timestamp':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),'kind':kind,'payload':fields}
    r.events.append(event)
    if kind in {'run.completed','run.failed','run.cancelled'}:
        r.terminal=True;r.status=kind.split('.')[1];r.approval_id=None
        if session_writers.get(r.session_id)==r.id:session_writers.pop(r.session_id,None)
        record(kind,run_id=r.id,session_id=r.session_id,sequence=r.sequence,elapsed_ms=int((time.monotonic()-r.created)*1000))
    r.changed.set()
    return f'event: pulse\ndata: {json.dumps(event,ensure_ascii=False)}\n\n'

async def translate(stream,r):
    answer='';pending='';last_flush=0;new_segment=True
    async for event in stream:
        data=event.data;kind=event.type
        if kind==EventType.REASONING_DELTA:
            continue
        if kind==EventType.ASSISTANT_DELTA:
            if new_segment:
                answer='';new_segment=False
                event_line(r,'answer.reset')
            delta=data.get('text','');answer+=delta;pending+=delta
            if len(answer.encode())>MAX_ANSWER:raise ValueError('Answer limit')
            if time.monotonic()-last_flush>=.04:
                event_line(r,'answer.delta',{'text':pending});pending='';last_flush=time.monotonic()
            continue
        if pending:event_line(r,'answer.delta',{'text':pending});pending=''
        if kind==EventType.ASSISTANT_MESSAGE:
            answer=data.get('text') or ''
            if data.get('tool_calls'):
                event_line(r,'answer.interim',{'text':answer});answer=''
            new_segment=True
            if data.get('usage'):
                usage=data['usage']
                record('provider.usage',run_id=r.id,provider=r.config.provider,count=sum(int(usage.get(key,0)) for key in ('input','output','cache_read','cache_write')))
        elif kind==EventType.TOOL_STARTED:
            event_line(r,'tool.started',{'tool_call_id':data.get('tool_call_id'),'title':title_for(data['name'])})
        elif kind==EventType.TOOL_FINISHED:
            event_line(r,'tool.completed' if data.get('status')=='ok' else 'tool.failed',
                       {'tool_call_id':data.get('tool_call_id'),'title':title_for(data['name']),
                        'detail':data.get('detail',data.get('result_preview','')),'status':data.get('status')})
        elif kind==EventType.PERMISSION_REQUIRED:
            r.approval_id=data['approval_id'];r.status='waiting'
            evidence=data['detail'];interaction=data.get('interaction','action')
            event_line(r,'approval.requested',{'approval_id':r.approval_id,'title':evidence.get('question','Review investigation plan') if interaction!='action' else title_for(data['name']),
                       'detail':evidence,'interaction':interaction,'options':evidence.get('options',[]) if interaction=='question' else []})
            event_line(r,'run.paused')
        elif kind in {EventType.COMPACTING,EventType.COMPACTED,EventType.CONTINUATION}:
            event_line(r,'answer.interim',{'text':data.get('text') or ('Condensing earlier context; full conversation remains saved.' if kind==EventType.COMPACTING else 'Context updated.')})
        elif kind==EventType.ERROR:
            record('provider.failed',run_id=r.id,error_type=data.get('error_type','ProviderError'))
            raise RuntimeError('Provider rejected or interrupted the request')
        elif kind==EventType.INTERRUPTED:
            r.cancelled=True
        elif kind==EventType.TURN_END:
            if data.get('status')!='completed':raise RuntimeError('Run stopped at its iteration or output limit')
        await r.agent.checkpoint(r.status)
    if pending:event_line(r,'answer.delta',{'text':pending})
    if not r.cancelled:event_line(r,'answer.final',{'text':answer})

async def serve(r):
    event_line(r,'run.started',{'provider':r.config.provider,'model':r.config.model})
    usage_changed=asyncio.Event();loop=asyncio.get_running_loop()
    r.agent.meter.on_change=lambda:loop.call_soon_threadsafe(usage_changed.set)
    async def publish_usage():
        while True:
            await usage_changed.wait();usage_changed.clear()
            try:
                snapshot=await asyncio.to_thread(r.agent.store.usage,r.session_id)
                event_line(r,'usage.updated',{'usage':snapshot})
            except Exception as exc:record('usage.failed',run_id=r.id,error_type=type(exc).__name__)
    usage_task=asyncio.create_task(publish_usage())
    try:
        async with asyncio.timeout(RUN_TTL):
            await translate(r.agent.run(r.message),r)
        await r.agent.checkpoint('cancelled' if r.cancelled else 'completed')
        event_line(r,'usage.updated',{'usage':await asyncio.to_thread(r.agent.store.usage,r.session_id)})
        if not r.cancelled and r.config.ready:titles.start(r.agent.store,r.config,r.session_id)
        event_line(r,'run.cancelled' if r.cancelled else 'run.completed')
    except asyncio.CancelledError:
        r.cancelled=True;r.agent.request_interrupt()
        await r.agent.checkpoint('cancelled')
        event_line(r,'run.cancelled',{'text':'Stop requested; already-started actions may finish.'})
    except Exception as exc:
        record('run.error',run_id=r.id,session_id=r.session_id,error_type=type(exc).__name__)
        try:await r.agent.checkpoint('failed')
        except Exception as failure:record('storage.failed',run_id=r.id,error_type=type(failure).__name__)
        event_line(r,'run.failed',{'text':'Request stopped. Check provider configuration or available context; earlier conversation remains saved. Inspect completed actions before retrying.'})
    finally:
        r.agent.meter.on_change=lambda:None
        usage_task.cancel()
        await asyncio.gather(usage_task,return_exceptions=True)
        r.agent.request_interrupt()
        if r.agent.pending:
            try:await asyncio.to_thread(r.agent.store.resolve,r.agent.pending['id'],r.id,False)
            except Exception as exc:record('storage.failed',run_id=r.id,error_type=type(exc).__name__)
        if not r.terminal:
            event_line(r,'run.failed',{'text':'Run stopped while saving state. Inspect earlier completed actions before retrying.'})
        client=getattr(r.agent.provider,'_client',None)
        if client and hasattr(client,'close'):
            try:await asyncio.wait_for(asyncio.to_thread(client.close),timeout=2)
            except Exception:pass
        r.changed.set()

async def observe(r,after=0):
    cursor=after
    while True:
        if r.events and cursor<r.events[0]['sequence']-1:
            # Active observer fell behind. Stop stream explicitly; history/replay exposes the gap.
            yield 'event: replay-gap\ndata: {}\n\n';return
        events=[event for event in r.events if event['sequence']>cursor]
        for event in events:
            cursor=event['sequence']
            yield f'event: pulse\ndata: {json.dumps(event,ensure_ascii=False)}\n\n'
            if event['kind']=='run.paused':return
        if r.terminal:return
        r.changed.clear()
        if r.sequence>cursor:continue
        try:await asyncio.wait_for(r.changed.wait(),timeout=15)
        except TimeoutError:yield ': heartbeat\n\n'

def prune():
    for identifier,r in list(runs.items()):
        if r.terminal and (time.monotonic()-r.created>RUN_TTL or len(runs)>=MAX_RUNS):del runs[identifier]
    for identifier,created in list(cancelled_requests.items()):
        if time.monotonic()-created>RUN_TTL:cancelled_requests.pop(identifier,None)

@app.get('/status',dependencies=[Depends(require_token)])
async def status():
    prune()
    return {'status':'ok','has_api_key':configuration.ready,'summary':'Ready','model':configuration.model,'provider':configuration.provider,
            'memory_enabled':configuration.memory_enabled,'active_runs':len(session_writers),'engine':'openworker','background_jobs':len(titles.jobs)}

@app.post('/config',dependencies=[Depends(require_token)])
async def configure(request:ProviderConfiguration):
    global configuration
    if session_writers and request.memory_enabled!=configuration.memory_enabled:raise HTTPException(409,'Stop active runs before changing memory')
    configuration=request
    return {'status':'updated'}

@app.post('/runs',dependencies=[Depends(require_token)])
async def run(request:RunRequest):
    if len(request.message.encode())>12000:raise HTTPException(422,'Message exceeds byte limit')
    if not configuration.ready:raise HTTPException(409,'Configure a provider first')
    sid=request.session_id or str(uuid.uuid4())
    try:uuid.UUID(sid)
    except ValueError:raise HTTPException(422,'Invalid session ID')
    prune()
    rid=request.request_id or str(uuid.uuid4())
    try:uuid.UUID(rid)
    except ValueError:raise HTTPException(422,'Invalid request ID')
    if rid in cancelled_requests:raise HTTPException(409,'Request was stopped before startup completed')
    existing=runs.get(rid)
    if existing:
        if existing.session_id!=sid or existing.message!=request.message or existing.agent.read_only!=(request.mode=='investigate') or getattr(existing.agent,'specialist','general')!=request.specialist:raise HTTPException(409,'Request ID already used')
        return StreamingResponse(observe(existing),media_type='text/event-stream')
    if sid in session_writers:raise HTTPException(409,'Conversation has an active run')
    if len(session_writers)>=4 or len(runs)>=MAX_RUNS:raise HTTPException(429,'Agent capacity reached')
    config=configuration.model_copy(deep=True)
    session_writers[sid]=rid  # Reserve before construction yields.
    try:
        db=await asyncio.to_thread(storage)
        try:
            snapshot=await native_request(rid,sid,['context'],timeout=2)
            context='Timestamped native snapshot (may be stale): '+snapshot['json'][:6000]
        except Exception:context='Native snapshot unavailable; request relevant evidence when needed.'
        memory=PulseMemoryStore(sid,config.memory_enabled,store=db)
        agent=await asyncio.to_thread(PulseTurnEngine,configuration=config,store=db,session_id=sid,run_id=rid,context=context,memory=memory,read_only=request.mode=='investigate',specialist=request.specialist)
        if rid in cancelled_requests:
            session_writers.pop(sid,None)
            raise HTTPException(409,'Request was stopped during setup')
        r=Run(rid,sid,agent,config,message=request.message);runs[rid]=r
        r.task=asyncio.create_task(serve(r))
    except HTTPException:
        raise
    except BaseException as exc:
        session_writers.pop(sid,None);record('run.setup_failed',run_id=rid,error_type=type(exc).__name__)
        if isinstance(exc,asyncio.CancelledError):raise
        raise HTTPException(503,'Agent runtime, migration or bundled skill unavailable')
    return StreamingResponse(observe(r),media_type='text/event-stream',headers={'Cache-Control':'no-cache'})

@app.post('/runs/{run_id}/continue',dependencies=[Depends(require_token)])
async def continue_run(run_id:str,request:ContinueRequest):
    r=runs.get(run_id)
    if not r or r.terminal or r.cancelled or r.approval_id!=request.approval_id or not r.agent.decision or r.agent.decision.done():
        raise HTTPException(409,'Approval unavailable or already resolved')
    is_question=r.agent.pending and r.agent.pending.get('kind')=='question'
    if is_question and (request.answer is None or not request.answer.strip() or len(request.answer.encode())>12000):
        raise HTTPException(422,'Supply a non-empty bounded answer')
    if not is_question and request.answer is not None:raise HTTPException(422,'Answers cannot approve actions')
    if not await asyncio.to_thread(r.agent.store.resolve,request.approval_id,run_id,True if is_question else request.approved):
        raise HTTPException(409,'Approval expired or already resolved')
    # Recheck after SQLite yielded: Stop can arrive while the decision commits.
    if r.cancelled or r.terminal or not r.agent.decision or r.agent.decision.done():raise HTTPException(409,'Run stopped')
    after=r.sequence;r.approval_id=None;r.status='running'
    event_line(r,'approval.resolved',{'approval_id':request.approval_id,'text':'Answered' if is_question else 'Approved' if request.approved else 'Declined'})
    r.agent.decision.set_result(request.answer if is_question else request.approved)
    return StreamingResponse(observe(r,after),media_type='text/event-stream',headers={'Cache-Control':'no-cache'})

@app.post('/runs/{run_id}/cancel',dependencies=[Depends(require_token)])
async def cancel(run_id:str):
    r=runs.get(run_id)
    if not r:
        try:uuid.UUID(run_id)
        except ValueError:raise HTTPException(422,'Invalid run ID')
        cancelled_requests[run_id]=time.monotonic()
        while len(cancelled_requests)>128:cancelled_requests.popitem(last=False)
        return {'cancelled':True}
    if r.terminal:return {'cancelled':r.cancelled}
    r.cancelled=True;r.agent.request_interrupt()
    try:await native_request(r.id,r.session_id,[],timeout=2,cancel=True)
    except Exception:pass
    # OpenWorker interruption preserves partial output and closes dangling calls.
    # Cancelling the entire generator immediately would skip that repair path.
    return {'cancelled':True}

@app.get('/runs/{run_id}/stream',dependencies=[Depends(require_token)])
async def reconnect(run_id:str,after_sequence:int=Query(0,ge=0)):
    r=runs.get(run_id)
    if not r:raise HTTPException(404,'Run unavailable after restart or expiry')
    if r.events and after_sequence<r.events[0]['sequence']-1:raise HTTPException(410,'Replay gap; reload conversation history')
    if r.status=='waiting' and r.agent.pending and after_sequence>=r.sequence:
        pending=r.agent.pending;evidence=pending['evidence'];interaction=pending.get('kind','action')
        event_line(r,'approval.requested',{'approval_id':pending['id'],'title':evidence.get('question','Review investigation plan') if interaction!='action' else title_for(pending['call'].name),
                   'detail':evidence,'interaction':interaction,'options':evidence.get('options',[])})
        event_line(r,'run.paused')
    return StreamingResponse(observe(r,after_sequence),media_type='text/event-stream',headers={'Cache-Control':'no-cache'})

@app.get('/runs/{run_id}/events',dependencies=[Depends(require_token)])
async def replay(run_id:str,after_sequence:int=Query(0,ge=0)):
    r=runs.get(run_id)
    if not r:raise HTTPException(404,'Replay expired')
    if r.events and after_sequence<r.events[0]['sequence']-1:raise HTTPException(410,'Replay gap; reload history')
    return {'events':[event for event in r.events if event['sequence']>after_sequence]}

@app.get('/sessions',dependencies=[Depends(require_token)])
async def sessions(page:int=Query(1,ge=1,le=10000),query:str=Query('',max_length=200),archived:bool=False):
    return {'sessions':await asyncio.to_thread(storage().sessions,page,query,archived)}

@app.get('/sessions/{session_id}/usage',dependencies=[Depends(require_token)])
async def session_usage(session_id:str):
    try:uuid.UUID(session_id)
    except ValueError:raise HTTPException(422,'Invalid session ID')
    return await asyncio.to_thread(storage().usage,session_id)

@app.get('/sessions/{session_id}/history',dependencies=[Depends(require_token)])
async def session_history(session_id:str,page:int=Query(1,ge=1,le=10000)):
    return await asyncio.to_thread(storage().history,session_id,page)

@app.get('/memory',dependencies=[Depends(require_token)])
async def memories():
    return {'memories':await PulseMemoryStore('',True,store=storage()).arecall(),'enabled':configuration.memory_enabled,'instructions':await asyncio.to_thread(storage().setting,'user_instructions','')}

@app.delete('/memory/{memory_id}',dependencies=[Depends(require_token)])
async def delete_memory(memory_id:str):
    if session_writers:raise HTTPException(409,'Stop active runs before changing memory')
    rows=await PulseMemoryStore('',store=storage()).arecall()
    if memory_id!='all' and not any(row['id']==memory_id for row in rows):raise HTTPException(404,'Memory unavailable')
    await asyncio.to_thread(storage().delete_memory,memory_id)
    return {'status':'deleted'}

@app.post('/memory/toggle',dependencies=[Depends(require_token)])
async def toggle_memory(enabled:bool):
    global configuration
    if session_writers:raise HTTPException(409,'Stop active runs before changing memory')
    configuration=configuration.model_copy(update={'memory_enabled':enabled})
    return {'enabled':enabled}


class SessionUpdate(BaseModel):
    title:Optional[str]=Field(default=None,min_length=1,max_length=80)
    pinned:Optional[bool]=None
    archived:Optional[bool]=None

@app.patch('/sessions/{session_id}',dependencies=[Depends(require_token)])
async def update_session(session_id:str,request:SessionUpdate):
    if session_id in session_writers:raise HTTPException(409,'Wait for the conversation to finish')
    try:await asyncio.to_thread(storage().update_session,session_id,**request.model_dump())
    except ValueError as exc:raise HTTPException(422,str(exc))
    return {'status':'updated'}

@app.get('/sessions/{session_id}/title',dependencies=[Depends(require_token)])
async def session_title(session_id:str):
    await titles.wait(session_id)
    return await asyncio.to_thread(storage().session_metadata,session_id)

class MemoryUpdate(BaseModel):
    content:str=Field(min_length=1,max_length=400)
    evidence:str=Field(min_length=1,max_length=400)
    kind:Literal['preference','lesson']='preference'
    revision:int=Field(default=0,ge=0)

@app.post('/memory',dependencies=[Depends(require_token)])
async def add_memory(request:MemoryUpdate):
    if session_writers:raise HTTPException(409,'Stop active runs before changing memory')
    result=await PulseMemoryStore('',configuration.memory_enabled,storage()).save_pulse_memory(request.content,request.evidence,request.kind)
    if 'error' in result:raise HTTPException(422,result['error'])
    return result

@app.put('/memory/{memory_id}',dependencies=[Depends(require_token)])
async def edit_memory(memory_id:str,request:MemoryUpdate):
    if session_writers:raise HTTPException(409,'Stop active runs before changing memory')
    try:result=await PulseMemoryStore('',configuration.memory_enabled,storage()).edit_memory(memory_id,request.content,request.evidence,request.kind,request.revision)
    except ValueError as exc:raise HTTPException(409,str(exc))
    if 'error' in result:raise HTTPException(422,result['error'])
    return result

class InstructionUpdate(BaseModel):
    text:str=Field(max_length=4000)

@app.put('/instructions',dependencies=[Depends(require_token)])
async def update_instructions(request:InstructionUpdate):
    if session_writers:raise HTTPException(409,'Stop active runs before changing instructions')
    try:await asyncio.to_thread(storage().set_setting,'user_instructions',request.text.strip())
    except ValueError as exc:raise HTTPException(422,str(exc))
    return {'status':'saved'}

@app.get('/sessions/{session_id}/tasks',dependencies=[Depends(require_token)])
async def session_tasks(session_id:str):
    return {'tasks':await asyncio.to_thread(storage().tasks,session_id)}


class MemoryUndo(BaseModel):
    revision:int=Field(ge=0)

@app.post('/memory/{memory_id}/undo',dependencies=[Depends(require_token)])
async def undo_memory(memory_id:str,request:MemoryUndo):
    if session_writers:raise HTTPException(409,'Wait for active runs before changing memory')
    if not await asyncio.to_thread(storage().undo_memory_save,memory_id,request.revision):raise HTTPException(409,'Memory changed or was already removed')
    return {'status':'undone'}

if __name__=='__main__':
    import uvicorn
    async def main():
        service=uvicorn.Server(uvicorn.Config(app,host='127.0.0.1',port=int(os.getenv('PULSE_AGENT_PORT','7777')),access_log=False))
        parent=int(os.getenv('PULSE_PARENT_PID','0'))
        async def watch_parent():
            while not service.should_exit:
                if parent and os.getppid()!=parent:service.should_exit=True;return
                await asyncio.sleep(2)
        watcher=asyncio.create_task(watch_parent())
        try:await service.serve()
        finally:watcher.cancel()
    asyncio.run(main())

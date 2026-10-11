import React, { useEffect, useMemo, useState, useRef, memo } from 'react';
import { createRoot } from 'react-dom/client';
import { AssistantRuntimeProvider, useExternalStoreRuntime, ThreadPrimitive, MessagePrimitive, ComposerPrimitive, ActionBarPrimitive, useAuiState, type ThreadMessageLike, type ToolCallMessagePartProps } from '@assistant-ui/react';
import { MarkdownTextPrimitive } from '@assistant-ui/react-markdown';
import remarkGfm from 'remark-gfm';
import { Activity, ArrowUp, ArrowDown, Plus, SlidersHorizontal, Brain, X, Copy, Check, ChevronRight, CircleStop, RotateCcw, ShieldCheck, Cpu, HardDrive, Layers } from 'lucide-react';
import { command, initial, type Snapshot, type Item } from './bridge';
import './style.css';

const Markdown = memo(function Markdown() { return <MarkdownTextPrimitive className="markdown" remarkPlugins={[remarkGfm]} smooth={false} defer skipHtml components={{img: () => null}} />; });

function ToolCard({toolName, args, result, status}: ToolCallMessagePartProps) {
  const data = args as unknown as Item;
  if (toolName === 'pulse_approval') return <section className="approval"><div className="approval-title"><ShieldCheck size={20}/><strong>{data.title}</strong></div><p>Review the affected items in the preview before continuing.</p><pre>{data.detail}</pre><div className="approval-actions"><button onClick={() => command('approve', {id:data.approvalID, approved:false})} disabled={!data.isRunning}>Decline</button><button className="primary" onClick={() => command('approve', {id:data.approvalID, approved:true})} disabled={!data.isRunning}>Approve this action</button></div><small>Earlier completed actions remain in effect.</small></section>;
  return <details className="tool"><summary><ChevronRight size={14}/><span>{data.title}</span><span className="tool-state">{data.isRunning || status.type === 'running' ? 'Running' : 'Done'}</span></summary><pre>{typeof result === 'string' ? result : data.detail}</pre></details>;
}
function Message() {
  const role = useAuiState(s => s.message.role);
  const text = useAuiState(s => s.message.content.filter(p=>p.type==='text').map(p=>p.text).join('\n'));
  const [copied,setCopied]=useState(false);
  return <MessagePrimitive.Root className={`message ${role}`}>
    {role === 'assistant' && <div className="message-label"><Activity size={15}/> Pulse</div>}
    <MessagePrimitive.Parts components={{Text: Markdown, tools:{Fallback:ToolCard}}}/>
    {role === 'assistant' && text.length > 0 && <ActionBarPrimitive.Root className="message-actions" hideWhenRunning><button aria-label="Copy answer" onClick={()=>{command('copy',{text});setCopied(true);setTimeout(()=>setCopied(false),1500)}}>{copied?<Check size={13}/>:<Copy size={13}/>}<span>{copied?'Copied':'Copy'}</span></button></ActionBarPrimitive.Root>}
  </MessagePrimitive.Root>;
}
function toMessages(items: Item[]): ThreadMessageLike[] {
  const result: ThreadMessageLike[] = [];
  for (let i=0;i<items.length;i++) {
    const item = items[i];
    if (item.kind === 'progress') continue;
    if (item.kind === 'user' || item.kind === 'answer' || item.kind === 'error') {
      result.push({id:item.id, role:item.kind === 'user' ? 'user':'assistant', content:[{type:'text',text:item.kind === 'user' ? item.title : item.detail}], ...(item.kind === 'answer' && item.isRunning ? {status:{type:'running'}} : {})});
    } else {
      const tools = [item];
      if (item.kind === 'tool') while (items[i+1]?.kind === 'tool') tools.push(items[++i]);
      result.push({id:item.id, role:'assistant', content:tools.map(t => ({type:'tool-call' as const, toolCallId:t.id, toolName:t.kind === 'approval'?'pulse_approval':'pulse_tool', args:{...t}, argsText:JSON.stringify(t), ...(t.isRunning && t.kind === 'tool'? {} : {result:t.detail})}))});
    }
  }
  return result;
}
const suggestions = [
  {icon:Cpu, title:'Why does my Mac feel slow?', detail:'Check pressure and busy apps'},
  {icon:HardDrive, title:'What is taking up space?', detail:'Find evidence before cleanup'},
  {icon:Layers, title:'Which apps are busy?', detail:'Inspect current activity'},
];
function App() {
  const [state,setState]=useState<Snapshot>(initial);
  const [memoryOpen,setMemoryOpen]=useState(false);
  const [clearConfirm,setClearConfirm]=useState(false);
  const memoryRef=useRef<HTMLElement>(null);
  useEffect(()=>{
    if(!memoryOpen)return;
    const previous=document.activeElement as HTMLElement|null;
    const node=memoryRef.current;
    const controls=()=>node?.querySelectorAll<HTMLElement>('button:not(:disabled),input:not(:disabled),summary');
    controls()?.[0]?.focus();
    const trap=(event:KeyboardEvent)=>{
      if(event.key==='Escape'){setMemoryOpen(false);return;}
      if(event.key!=='Tab')return;
      const list=controls();if(!list?.length)return;
      const first=list[0],last=list[list.length-1];
      if(event.shiftKey&&document.activeElement===first){event.preventDefault();last.focus();}
      else if(!event.shiftKey&&document.activeElement===last){event.preventDefault();first.focus();}
    };
    document.addEventListener('keydown',trap);
    return()=>{document.removeEventListener('keydown',trap);previous?.focus()};
  },[memoryOpen]);
  useEffect(() => { window.pulseReceive=setState; command('ready'); return () => { delete window.pulseReceive; }; },[]);
  const items = useMemo(() => state.items.map(i => i.kind === 'answer' && i.id === state.items.findLast(x=>x.kind === 'answer')?.id && state.state === 'running' ? {...i,isRunning:true} : i),[state.items,state.state]);
  const messages = useMemo(()=>toMessages(items),[items]);
  const runtime=useExternalStoreRuntime({messages, isRunning:state.busy && state.state!=='starting', isDisabled:!state.ready || state.state==='starting',
    onNew:async message => { const text=message.content.filter(p=>p.type==='text').map(p=>p.text).join('\n'); command('send',{text}); },
    onCancel:async()=>command('stop'), convertMessage:m=>m});
  const working=state.busy && state.state!=='starting';
  return <AssistantRuntimeProvider runtime={runtime}><div className={`workspace ${state.largerText?'larger':''}`}>
    <aside className="rail"><div className="rail-heading"><span>Conversations</span><button title="New conversation" aria-label="New conversation" disabled={state.busy} onClick={()=>command('new')}><Plus size={16}/></button></div>
      <button className={`session ${!state.sessionId?'selected':''}`} onClick={()=>command('new')} disabled={state.busy}><Activity size={15}/><span>New conversation</span></button>
      <div className="sessions">{state.sessions.map(s=><button key={s.sessionId} className={`session ${state.sessionId===s.sessionId?'selected':''}`} title={s.name} disabled={state.busy} onClick={()=>command('session',{id:s.sessionId})}><span>{s.name}</span></button>)}{!state.sessions.length && <p className="rail-empty">Your conversations stay on this Mac.</p>}</div>
      <div className="rail-bottom"><button onClick={()=>{setMemoryOpen(true);command('memory')}}><Brain size={16}/>Memory<span className="tag">{state.memoryEnabled?'On':'Off'}</span></button><button onClick={()=>command('settings')}><SlidersHorizontal size={16}/>Provider settings</button></div>
    </aside>
    <main className="main"><header className="header"><div className="identity"><span className="pulse-mark"><Activity size={22}/></span><div><h1>Ask Pulse</h1><p>A clearer picture of your Mac.</p></div></div><button className="model-picker" onClick={()=>command('settings')} title="Change provider and model"><span className={`status-dot ${state.ready?'connected':''}`}/><span>{state.model||'Choose a model'}</span><SlidersHorizontal size={13}/></button></header>
      {!state.ready && state.state!=='starting' ? <section className="setup"><span className="hero-icon"><Activity size={35}/></span><h2>Your Mac. Your model.</h2><p>Connect an AI provider or a local model to ask about performance, storage and the apps you use.</p><button className="primary" onClick={()=>command('settings')}>Connect a model <ChevronRight size={16}/></button><button className="quiet" onClick={()=>command('reconnect')}><RotateCcw size={14}/>Check setup again</button><small>Your selected provider receives your questions and requested diagnostic results. Provider charges may apply.</small></section>:
      <ThreadPrimitive.Root className="thread"><ThreadPrimitive.Viewport className="viewport" autoScroll><div className="transcript"><ThreadPrimitive.Empty><section className="welcome"><span className="hero-icon"><Activity size={35}/></span><p className="eyebrow">ASK. INVESTIGATE. UNDERSTAND.</p><h2>What’s on your mind?</h2><p className="welcome-detail">A slow afternoon. A full disk. An app that won’t settle.<br/>Let’s find out what your Mac is telling us.</p><div className="suggestions">{suggestions.map(s=><button key={s.title} disabled={!state.ready||state.busy} onClick={()=>command('send',{text:s.title})}><s.icon size={19}/><strong>{s.title}</strong><span>{s.detail}</span><ChevronRight className="suggestion-arrow" size={15}/></button>)}</div><div className="evidence-note"><ShieldCheck size={14}/>Evidence first. You approve every change.</div></section></ThreadPrimitive.Empty>
        {state.hasEarlier && <button className="history-more quiet" disabled={state.busy} onClick={()=>command('older')}>Load earlier messages</button>}
        <ThreadPrimitive.Messages components={{Message}}/>
      </div><ThreadPrimitive.ScrollToBottom className="jump" aria-label="Jump to latest"><ArrowDown size={15}/>Latest</ThreadPrimitive.ScrollToBottom></ThreadPrimitive.Viewport>
      <div className="composer-area"><div className="run-status" role="status"><span className={`status-dot ${working?'connected':''}`}/>{state.status}{state.state==='failed'&&<button onClick={()=>command('reconnect')}>Reconnect</button>}</div>
        <ComposerPrimitive.Root className="composer"><ComposerPrimitive.Input placeholder="Ask about your Mac…" aria-label="Question for Pulse" autoFocus rows={2}/><div className="composer-controls"><span className="composer-hint"><ShieldCheck size={13}/>Changes need your approval</span>{state.state === 'starting' ? <button className="send" disabled aria-label="Starting local agent"><Activity size={20}/></button> : state.busy ? <ComposerPrimitive.Cancel className="send" aria-label="Stop run"><CircleStop size={20}/></ComposerPrimitive.Cancel>:<ComposerPrimitive.Send className="send" aria-label="Send question"><ArrowUp size={19}/></ComposerPrimitive.Send>}</div></ComposerPrimitive.Root>
        <p className="composer-footnote">Pulse can make mistakes. Check the evidence before approving an action.</p></div></ThreadPrimitive.Root>}
    </main>
    {memoryOpen&&<div className="modal-backdrop" onClick={()=>setMemoryOpen(false)}><section ref={memoryRef} className="memory-panel" role="dialog" aria-modal="true" aria-labelledby="memory-title" onClick={e=>e.stopPropagation()} onKeyDown={e=>{if(e.key==='Escape')setMemoryOpen(false)}}><header><div><p className="eyebrow">ON THIS MAC</p><h2 id="memory-title">A little context goes a long way.</h2></div><button autoFocus aria-label="Close memory" onClick={()=>setMemoryOpen(false)}><X size={18}/></button></header><p>Useful preferences and lessons from your conversations. You can review and remove them at any time.</p><label className="memory-toggle"><Brain size={18}/><span>Use and save memory</span><input type="checkbox" checked={state.memoryEnabled} disabled={state.busy} onChange={e=>command('memoryToggle',{enabled:e.target.checked})}/></label><p className="memory-status" role="status">{state.memoryStatus}</p><div className="memory-list">{state.memories.length?state.memories.map(m=><article key={m.id}><span className="tag">{m.kind}</span><p>{m.content}</p><details><summary>Source evidence</summary><p>{m.evidence}</p><small>{new Date(m.created_at*1000).toLocaleDateString()}</small></details><button className="quiet" disabled={state.busy} onClick={()=>command('memoryDelete',{id:m.id})}>Remove</button></article>):<div className="memory-empty"><Brain size={28}/><h3>Room for what matters.</h3><p>When something useful is remembered, it will appear here.</p></div>}</div><footer>{clearConfirm?<><span>Remove all saved memories?</span><button onClick={()=>setClearConfirm(false)}>Keep memories</button><button className="danger" disabled={state.busy} onClick={()=>{command('memoryDelete',{id:'all'});setClearConfirm(false)}}>Remove all</button></>:<button className="quiet" disabled={state.busy||!state.memories.length} onClick={()=>setClearConfirm(true)}>Clear all memories</button>}</footer></section></div>}
  </div></AssistantRuntimeProvider>;
}
createRoot(document.getElementById('root')!).render(<App/>);

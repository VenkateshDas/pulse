// Conversation surface adapted from OpenWorker's Transcript/Composer (MIT).
// Native Pulse remains authoritative for state, credentials, drafts and approvals.
import React, { useEffect, useLayoutEffect, useMemo, useState, useRef, useId, memo } from 'react';
import { createRoot } from 'react-dom/client';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import { Activity, ArrowUp, ArrowDown, Plus, SlidersHorizontal, Brain, X, Copy, Check, ChevronRight, CircleStop, RotateCcw, ShieldCheck, Cpu, HardDrive, Layers } from 'lucide-react';
import { command, initial, applyPatch, type Snapshot, type Item } from './bridge';
import { groupTimeline } from './timeline';
import './style.css';

const Markdown = memo(function Markdown({text}: {text:string}) {
  return <div className="markdown"><ReactMarkdown remarkPlugins={[remarkGfm]} skipHtml components={{img:()=>null}}>{text}</ReactMarkdown></div>;
});
function CopyAnswer({text}:{text:string}) {
  const id=useId(); const [copied,setCopied]=useState(false);
  useEffect(()=>{
    let timer:ReturnType<typeof setTimeout>;
    const ack=(event:Event)=>{ const result=(event as CustomEvent).detail;
      if(result?.id===id && result.success){setCopied(true);timer=setTimeout(()=>setCopied(false),1500)} };
    window.addEventListener('pulse-copy',ack);
    return()=>{window.removeEventListener('pulse-copy',ack);clearTimeout(timer)};
  },[id]);
  return <div className="message-actions"><button onClick={()=>command('copy',{text,id})} aria-label="Copy answer">{copied?<Check size={13}/>:<Copy size={13}/>} {copied?'Copied':'Copy'}</button></div>;
}
function ReviewCard({item}:{item:Item}) {
  const [answer,setAnswer]=useState('');
  const active=item.isRunning;
  const tooLong=new TextEncoder().encode(answer).length>12000;
  if(item.interaction==='question') return <section className="approval" aria-label="Question from Pulse">
    <strong>{item.title}</strong><div className="question-options">{(item.options||[]).slice(0,8).map(option=><button key={option} disabled={!active} onClick={()=>command('answer',{id:item.approvalID,text:option})}>{option}</button>)}</div>
    {active?<form onSubmit={e=>{e.preventDefault();if(answer.trim()&&!tooLong)command('answer',{id:item.approvalID,text:answer})}}><label>Your answer<textarea value={answer} maxLength={12000} onChange={e=>setAnswer(e.target.value)} /></label>{tooLong&&<p role="alert">Answer exceeds 12,000 bytes. Shorten it before continuing.</p>}<button className="primary" disabled={!answer.trim()||tooLong}>Continue</button></form>:<small>{item.outcome||'Question no longer active'}</small>}
  </section>;
  const plan=item.interaction==='plan';
  return <section className="approval"><div className="approval-title"><ShieldCheck size={20}/><strong>{item.title}</strong></div>
    <p>{plan?'Review the investigation plan. Every later change still needs its own approval.':'Review the exact affected items before continuing.'}</p>
    <pre>{item.detail}</pre><div className="approval-actions"><button onClick={()=>command('approve',{id:item.approvalID,approved:false})} disabled={!active}>Decline</button><button className="primary" onClick={()=>command('approve',{id:item.approvalID,approved:true})} disabled={!active}>{plan?'Accept plan':'Approve this action'}</button></div>
    <small>{item.outcome||'Earlier completed actions remain in effect.'}</small></section>;
}
function Transcript({items}:{items:Item[]}) {
  const rows=useMemo(()=>groupTimeline(items),[items]);
  return <>{rows.map(row=>row.kind==='activity'?<details className="work-group" key={row.id}>
    <summary><ChevronRight size={14}/>{row.items.some(i=>i.isRunning)?'Working':'Investigation'} · {row.items.filter(i=>i.kind==='tool').length} {row.items.filter(i=>i.kind==='tool').length===1?'step':'steps'}</summary>
    {row.items.map(item=>item.kind==='tool'?<details className="tool" key={item.id}><summary><ChevronRight size={14}/><span>{item.title}</span><span className={`tool-state ${item.outcome==='error'?'failed':''}`}>{item.isRunning?'Running':item.outcome==='ok'?'Complete':item.outcome==='denied'?'Declined':item.outcome==='error'?'Failed':'Result'}</span></summary><pre>{item.detail}</pre></details>:<p className="progress" key={item.id}>{item.detail}</p>)}
    </details>:row.item.kind==='approval'?<ReviewCard item={row.item} key={row.id}/>:<article className={`message ${row.item.kind==='user'?'user':'assistant'}`} key={row.id}>
      {row.item.kind!=='user'&&<div className="message-label"><Activity size={15}/>Pulse</div>}
      {row.item.kind==='user'?<div className="markdown user-text">{row.item.title}</div>:row.item.isRunning?<div className="markdown streaming">{row.item.detail}</div>:<Markdown text={row.item.detail}/>}
      {row.item.kind==='answer'&&!row.item.isRunning&&<CopyAnswer text={row.item.detail}/>}
    </article>)}</>;
}

function compactTokens(value:number) {
  return value>=1000?`${(value/1000).toLocaleString(undefined,{maximumFractionDigits:1})}K`:value.toLocaleString();
}
const UsageDetails=memo(function UsageDetails({usage}:{usage:Snapshot['usage']}) {
  const dialog=useRef<HTMLDialogElement>(null);
  const trigger=useRef<HTMLButtonElement>(null);
  const title=useId();
  const context=usage?.context;
  const totals=usage?.totals;
  const partial=!!usage?.historical||!!totals?.missingCost;
  const percent=context&&context.limit>0?Math.round(context.estimatedTokens/context.limit*100):null;
  const contextText=context?`Context ~${compactTokens(context.estimatedTokens)} / ${compactTokens(context.limit)}${percent===null?'':` · ${percent}%`}`:'Context not measured';
  const tracked=!!totals&&(!usage?.historical||totals.requests>0);
  const tokens=tracked?`${totals.missingUsage||usage?.historical?'≥':''}${compactTokens(totals.totalTokens)} tokens`:'Untracked';
  const cost=totals?.costUSD;
  const costText=cost===null||cost===undefined?'Cost unavailable':`${partial?'≥':''}${Number(cost)>0&&Number(cost)<0.000001?`$${cost}`:new Intl.NumberFormat(undefined,{style:'currency',currency:'USD',minimumFractionDigits:2,maximumFractionDigits:6}).format(Number(cost))}`;
  const close=()=>{dialog.current?.close();trigger.current?.focus()};
  return <><button type="button" ref={trigger} className="usage-trigger" aria-haspopup="dialog" onClick={()=>dialog.current?.showModal()}><span>{contextText}</span><span className="usage-session">Session {tokens} · {costText}</span></button>
    <dialog ref={dialog} className="usage-panel" aria-labelledby={title} onCancel={e=>{e.preventDefault();close()}} onClick={e=>{if(e.target===e.currentTarget){const bounds=e.currentTarget.getBoundingClientRect();if(e.clientX<bounds.left||e.clientX>bounds.right||e.clientY<bounds.top||e.clientY>bounds.bottom)close()}}} onClose={()=>trigger.current?.focus()}>
      <header><h2 id={title}>Context and session usage</h2><button type="button" aria-label="Close usage details" onClick={close}><X size={18}/></button></header>
      <section><h3>Latest request context</h3>{context?<><p className="usage-total">~{context.estimatedTokens.toLocaleString()} <span>/ {context.limit.toLocaleString()} tokens{percent===null?'':` · ${percent}%`}</span></p><p>Estimated input for {context.purpose==='compaction'?'conversation summary':'your conversation'}. {context.model} · {new Date(context.measuredAt*1000).toLocaleTimeString(undefined,{hour:'2-digit',minute:'2-digit'})}</p><dl className="usage-breakdown">{context.categories.map(category=><div key={category.label}><dt>{category.label}</dt><dd>~{category.tokens.toLocaleString()}</dd></div>)}</dl><p className="usage-note">Category counts are estimates; provider tokenization may differ.</p><dl className="usage-breakdown"><div><dt>Reserved for output</dt><dd>{context.outputReserve.toLocaleString()}</dd></div><div><dt>Provider-reported input</dt><dd>{context.reportedTokens===undefined?'Unavailable':context.reportedTokens.toLocaleString()}</dd></div></dl><p className="usage-note">Output reserve is separate from input context. Context describes the latest measured request, not the sum of this session.</p></>:<p>No context measurement yet. Send a question to see what goes into the next request.</p>}</section>
      <section><h3>Session totals</h3>{tracked&&totals?<><p className="usage-total">{tokens} <span>· {costText}</span></p><dl className="usage-breakdown"><div><dt>Fresh input</dt><dd>{totals.input.toLocaleString()}</dd></div><div><dt>Output</dt><dd>{totals.output.toLocaleString()}</dd></div><div><dt>Cached input</dt><dd>{totals.cacheRead.toLocaleString()}</dd></div><div><dt>Cache writes</dt><dd>{totals.cacheWrite.toLocaleString()}</dd></div><div><dt>Conversation summaries</dt><dd>{totals.compactionTokens.toLocaleString()}</dd></div><div><dt>Model requests</dt><dd>{totals.requests.toLocaleString()}</dd></div></dl><p className="usage-note">Totals use provider-reported usage. Cached input is counted once; reasoning tokens are included in output when reported. Summary tokens are already included in session totals. Cost is in USD.</p></>:<p>Session usage has not been recorded.</p>}
      {!!totals?.missingUsage&&<p className="usage-warning">Usage unavailable for {totals.missingUsage} {totals.missingUsage===1?'request':'requests'}. Token totals are incomplete.</p>}
      {!!totals?.missingCost&&<p className="usage-warning">Cost unavailable for {totals.missingCost} {totals.missingCost===1?'request':'requests'}. Any amount shown is a known subtotal.</p>}
      {usage?.historical&&<p className="usage-warning">Earlier messages predate usage tracking. Their tokens and costs are unavailable.</p>}</section>
    </dialog></>;
});

const suggestions = [
  {icon:Cpu, title:'Why does my Mac feel slow?', detail:'Check pressure and busy apps'},
  {icon:HardDrive, title:'What is taking up space?', detail:'Find evidence before cleanup'},
  {icon:Layers, title:'Which apps are busy?', detail:'Inspect current activity'},
];
function App() {
  const [state,setState]=useState<Snapshot>(initial);
  const [draft,setDraft]=useState('');
  const [atBottom,setAtBottom]=useState(true);
  const viewport=useRef<HTMLDivElement>(null);
  const following=useRef(true);
  const session=useRef<string|undefined>(undefined);
  const received=useRef(false);
  const previous=useRef({height:0,first:''});
  useLayoutEffect(()=>{
    const node=viewport.current;if(!node)return;
    if(following.current)node.scrollTop=node.scrollHeight;
    else if(previous.current.first!==state.items[0]?.id)node.scrollTop+=node.scrollHeight-previous.current.height;
    previous.current={height:node.scrollHeight,first:state.items[0]?.id||''};
  },[state.items,atBottom]);
  useEffect(()=>{
    const node=viewport.current;const transcript=node?.firstElementChild;if(!node||!transcript)return;
    const observer=new ResizeObserver(()=>{if(following.current){node.scrollTop=node.scrollHeight;setAtBottom(true)}});
    observer.observe(transcript);return()=>observer.disconnect();
  },[state.ready]);
  const send=()=>{if(!draft.trim()||state.busy||!state.ready||new TextEncoder().encode(draft).length>12000)return;command('send',{text:draft});setDraft('');following.current=true;setAtBottom(true)};

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
  useEffect(()=>{
    window.pulseReceive=next=>{
      if(!received.current||session.current!==next.sessionId){setDraft(next.draft||'');following.current=true;setAtBottom(true)}
      received.current=true;session.current=next.sessionId;setState(next);
    };
    let latest=initial;window.pulsePatch=patch=>{latest=applyPatch(latest,patch);window.pulseReceive?.(latest)};
    command('ready');return()=>{delete window.pulseReceive;delete window.pulsePatch};
  },[]);
  const items = useMemo(()=>{const latest=state.items.findLast(i=>i.kind==='answer')?.id;return state.items.map(i=>i.kind==='answer'&&i.id===latest&&state.state==='running'?{...i,isRunning:true}:i)},[state.items,state.state]);
  const working=state.busy && state.state!=='starting';
  return <><div className={`workspace ${state.largerText?'larger':''}`}>
    <aside className="rail"><div className="rail-heading"><span>Conversations</span><button title="New conversation" aria-label="New conversation" disabled={state.busy} onClick={()=>command('new')}><Plus size={16}/></button></div>
      <button className={`session ${!state.sessionId?'selected':''}`} onClick={()=>command('new')} disabled={state.busy}><Activity size={15}/><span>New conversation</span></button>
      <div className="sessions">{state.sessions.map(s=><button key={s.sessionId} className={`session ${state.sessionId===s.sessionId?'selected':''}`} title={s.name} disabled={state.busy} onClick={()=>command('session',{id:s.sessionId})}><span>{s.name}</span></button>)}{!state.sessions.length && <p className="rail-empty">Your conversations stay on this Mac.</p>}</div>
      <div className="rail-bottom"><button onClick={()=>{setMemoryOpen(true);command('memory')}}><Brain size={16}/>Memory<span className="tag">{state.memoryEnabled?'On':'Off'}</span></button><button onClick={()=>command('settings')}><SlidersHorizontal size={16}/>Provider settings</button></div>
    </aside>
    <main className="main"><header className="header"><div className="identity"><span className="pulse-mark"><Activity size={22}/></span><div><h1>Ask Pulse</h1><p>A clearer picture of your Mac.</p></div></div><button className="model-picker" onClick={()=>command('settings')} title="Change provider and model"><span className={`status-dot ${state.ready?'connected':''}`}/><span>{state.model||'Choose a model'}</span><SlidersHorizontal size={13}/></button></header>
      {!state.ready && state.state!=='starting' ? <section className="setup"><span className="hero-icon"><Activity size={35}/></span><h2>Your Mac. Your model.</h2><p>Connect an AI provider or a local model to ask about performance, storage and the apps you use.</p><button className="primary" onClick={()=>command('settings')}>Connect a model <ChevronRight size={16}/></button><button className="quiet" onClick={()=>command('reconnect')}><RotateCcw size={14}/>Check setup again</button><small>Your selected provider receives your questions, a cached performance snapshot and requested diagnostic results. Provider charges may apply.</small></section>:
      <div className="thread"><div className="viewport" ref={viewport} onWheel={()=>{following.current=false}} onPointerDown={()=>{following.current=false}} onKeyDown={e=>{if(['PageUp','PageDown','Home','End','ArrowUp','ArrowDown'].includes(e.key))following.current=false}} onScroll={e=>{if(!following.current){const node=e.currentTarget;const near=node.scrollHeight-node.scrollTop-node.clientHeight<80;following.current=near;setAtBottom(near)}}}><div className="transcript">{!items.length && <section className="welcome"><span className="hero-icon"><Activity size={35}/></span><p className="eyebrow">ASK. INVESTIGATE. UNDERSTAND.</p><h2>What’s on your mind?</h2><p className="welcome-detail">A slow afternoon. A full disk. An app that won’t settle.<br/>Let’s find out what your Mac is telling us.</p><div className="suggestions">{suggestions.map(s=><button key={s.title} disabled={!state.ready||state.busy} onClick={()=>command('send',{text:s.title})}><s.icon size={19}/><strong>{s.title}</strong><span>{s.detail}</span><ChevronRight className="suggestion-arrow" size={15}/></button>)}</div><div className="evidence-note"><ShieldCheck size={14}/>Evidence first. You approve every change.</div></section>}
        {state.hasEarlier && <button className="history-more quiet" disabled={state.busy} onClick={()=>command('older')}>Load earlier messages</button>}
        <Transcript items={items}/>
      </div>{!atBottom&&<button className="jump" aria-label="Jump to latest" onClick={()=>{following.current=true;setAtBottom(true)}}><ArrowDown size={15}/>Latest</button>}</div>
      <div className="composer-area"><div className="run-status" role="status"><span className={`status-dot ${working?'connected':''}`}/>{state.status}{state.state==='failed'&&<button onClick={()=>command('reconnect')}>Reconnect</button>}</div>
        <form className="composer" onSubmit={e=>{e.preventDefault();send()}}><textarea placeholder="Ask about your Mac…" aria-label="Question for Pulse" autoFocus rows={2} value={draft} maxLength={12000} onChange={e=>{setDraft(e.target.value);command('draft',{text:e.target.value})}} onKeyDown={e=>{if(e.key==='Enter'&&!e.shiftKey&&!e.nativeEvent.isComposing){e.preventDefault();send()}}}/><div className="composer-controls"><label className="composer-hint"><ShieldCheck size={13}/><select aria-label="Agent mode" disabled={state.busy} value={state.readOnly?'investigate':'interactive'} onChange={e=>command('mode',{readOnly:e.target.value==='investigate'})}><option value="interactive">Ask before changes</option><option value="investigate">Investigate · read only</option></select></label><UsageDetails usage={state.usage}/>{state.state === 'starting' ? <button className="send" disabled aria-label="Starting local agent"><Activity size={20}/></button> : state.busy ? <button type="button" className="send" aria-label="Stop run" onClick={()=>command('stop')}><CircleStop size={20}/></button>:<button className="send" aria-label="Send question" disabled={!draft.trim()||!state.ready||new TextEncoder().encode(draft).length>12000}><ArrowUp size={19}/></button>}</div></form>
        <p className="composer-footnote">Pulse can make mistakes. Check the evidence before approving an action.</p></div></div>}
    </main>
    {memoryOpen&&<div className="modal-backdrop" onClick={()=>setMemoryOpen(false)}><section ref={memoryRef} className="memory-panel" role="dialog" aria-modal="true" aria-labelledby="memory-title" onClick={e=>e.stopPropagation()} onKeyDown={e=>{if(e.key==='Escape')setMemoryOpen(false)}}><header><div><p className="eyebrow">ON THIS MAC</p><h2 id="memory-title">A little context goes a long way.</h2></div><button autoFocus aria-label="Close memory" onClick={()=>setMemoryOpen(false)}><X size={18}/></button></header><p>Useful preferences and lessons from your conversations. You can review and remove them at any time.</p><label className="memory-toggle"><Brain size={18}/><span>Use and save memory</span><input type="checkbox" checked={state.memoryEnabled} disabled={state.busy} onChange={e=>command('memoryToggle',{enabled:e.target.checked})}/></label><p className="memory-status" role="status">{state.memoryStatus}</p><div className="memory-list">{state.memories.length?state.memories.map(m=><article key={m.id}><span className="tag">{m.kind}</span><p>{m.content}</p><details><summary>Source evidence</summary><p>{m.evidence}</p><small>{new Date(m.created_at*1000).toLocaleDateString()}</small></details><button className="quiet" disabled={state.busy} onClick={()=>command('memoryDelete',{id:m.id})}>Remove</button></article>):<div className="memory-empty"><Brain size={28}/><h3>Room for what matters.</h3><p>When something useful is remembered, it will appear here.</p></div>}</div><footer>{clearConfirm?<><span>Remove all saved memories?</span><button onClick={()=>setClearConfirm(false)}>Keep memories</button><button className="danger" disabled={state.busy} onClick={()=>{command('memoryDelete',{id:'all'});setClearConfirm(false)}}>Remove all</button></>:<button className="quiet" disabled={state.busy||!state.memories.length} onClick={()=>setClearConfirm(true)}>Clear all memories</button>}</footer></section></div>}
  </div></>;
}
createRoot(document.getElementById('root')!).render(<App/>);

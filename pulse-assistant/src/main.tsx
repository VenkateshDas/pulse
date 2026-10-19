// Conversation surface adapted from OpenWorker's Transcript/Composer (MIT).
// Native Pulse remains authoritative for state, credentials, drafts and approvals.
import React, { useEffect, useLayoutEffect, useMemo, useState, useRef, useId, memo } from 'react';
import { createRoot } from 'react-dom/client';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import { Activity, ArrowUp, ArrowDown, Plus, SlidersHorizontal, Brain, X, Copy, Check, ChevronRight, CircleStop, RotateCcw, ShieldCheck, Cpu, HardDrive, Layers, PanelRight, Paperclip, Mic, Download, ListChecks } from 'lucide-react';
import { command, initial, applyPatch, shouldSyncDraft, type Snapshot, type Item } from './bridge';
import { groupTimeline } from './timeline';
import './style.css';
import './home-assistant.css';
import {FeaturePage} from './Features';

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
  return <><button type="button" ref={trigger} className="usage-trigger" title={`${contextText}. Session ${tokens} · ${costText}`} aria-label="Context and session usage" aria-haspopup="dialog" onClick={()=>dialog.current?.showModal()}>Usage</button>
    <dialog ref={dialog} className="usage-panel" aria-labelledby={title} onCancel={e=>{e.preventDefault();close()}} onClick={e=>{if(e.target===e.currentTarget){const bounds=e.currentTarget.getBoundingClientRect();if(e.clientX<bounds.left||e.clientX>bounds.right||e.clientY<bounds.top||e.clientY>bounds.bottom)close()}}} onClose={()=>trigger.current?.focus()}>
      <header><h2 id={title}>Context and session usage</h2><button type="button" aria-label="Close usage details" onClick={close}><X size={18}/></button></header>
      <section><h3>Latest request context</h3>{context?<><p className="usage-total">~{context.estimatedTokens.toLocaleString()} <span>/ {context.limit.toLocaleString()} tokens{percent===null?'':` · ${percent}%`}</span></p><p>Estimated input for {context.purpose==='compaction'?'conversation summary':'your conversation'}. {context.model} · {new Date(context.measuredAt*1000).toLocaleTimeString(undefined,{hour:'2-digit',minute:'2-digit'})}</p><dl className="usage-breakdown">{context.categories.map(category=><div key={category.label}><dt>{category.label}</dt><dd>~{category.tokens.toLocaleString()}</dd></div>)}</dl><p className="usage-note">Category counts are estimates; provider tokenization may differ.</p><dl className="usage-breakdown"><div><dt>Reserved for output</dt><dd>{context.outputReserve.toLocaleString()}</dd></div><div><dt>Provider-reported input</dt><dd>{context.reportedTokens===undefined?'Unavailable':context.reportedTokens.toLocaleString()}</dd></div></dl><p className="usage-note">Output reserve is separate from input context. Context describes the latest measured request, not the sum of this session.</p></>:<p>No context measurement yet. Send a question to see what goes into the next request.</p>}</section>
      <section><h3>Session totals</h3><p>Includes conversation, title generation and requested independent reviews.</p>{tracked&&totals?<><p className="usage-total">{tokens} <span>· {costText}</span></p><dl className="usage-breakdown"><div><dt>Fresh input</dt><dd>{totals.input.toLocaleString()}</dd></div><div><dt>Output</dt><dd>{totals.output.toLocaleString()}</dd></div><div><dt>Cached input</dt><dd>{totals.cacheRead.toLocaleString()}</dd></div><div><dt>Cache writes</dt><dd>{totals.cacheWrite.toLocaleString()}</dd></div><div><dt>Conversation summaries</dt><dd>{totals.compactionTokens.toLocaleString()}</dd></div><div><dt>Model requests</dt><dd>{totals.requests.toLocaleString()}</dd></div></dl><p className="usage-note">Totals use provider-reported usage. Cached input is counted once; reasoning tokens are included in output when reported. Summary tokens are already included in session totals. Cost is in USD.</p></>:<p>Session usage has not been recorded.</p>}
      {!!totals?.missingUsage&&<p className="usage-warning">Usage unavailable for {totals.missingUsage} {totals.missingUsage===1?'request':'requests'}. Token totals are incomplete.</p>}
      {!!totals?.missingCost&&<p className="usage-warning">Cost unavailable for {totals.missingCost} {totals.missingCost===1?'request':'requests'}. Any amount shown is a known subtotal.</p>}
      {usage?.historical&&<p className="usage-warning">Earlier messages predate usage tracking. Their tokens and costs are unavailable.</p>}</section>
    </dialog></>;
});

const homeSuggestions = [
  {icon:Cpu, title:'Help with a slowdown', detail:'Review pressure and activity'},
  {icon:HardDrive, title:'Review storage options', detail:'Find evidence before cleanup'},
  {icon:Layers, title:'Explain these readings', detail:'Understand your Mac'},
];
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
    if(following.current)node.scrollTop=state.items.length?node.scrollHeight:0;
    else if(previous.current.first!==state.items[0]?.id)node.scrollTop+=node.scrollHeight-previous.current.height;
    previous.current={height:node.scrollHeight,first:state.items[0]?.id||''};
  },[state.items,atBottom]);
  useEffect(()=>{
    const node=viewport.current;const transcript=node?.firstElementChild;if(!node||!transcript)return;
    const observer=new ResizeObserver(()=>{if(following.current){node.scrollTop=node.querySelector('.message')?node.scrollHeight:0;setAtBottom(true)}});
    observer.observe(transcript);return()=>observer.disconnect();
  },[state.ready]);
  const send=()=>{if(!draft.trim()||state.busy||!state.ready||new TextEncoder().encode(draft).length>12000)return;command('send',{text:draft});setDraft('');following.current=true;setAtBottom(true)};

  const [drawer,setDrawer]=useState(false);
  const nativeDraft=useRef(0);
  const drawerClose=useRef<HTMLButtonElement>(null);
  const wasDrawer=useRef(false);
  const composer=useRef<HTMLTextAreaElement>(null);
  useEffect(()=>{if(state.ready)composer.current?.focus()},[state.ready]);
  useEffect(()=>{
    if(state.compact&&drawer)drawerClose.current?.focus();
    else if(wasDrawer.current)composer.current?.focus();
    wasDrawer.current=drawer;
  },[drawer,state.compact]);
  useEffect(()=>{setDrawer(false)},[state.compact]);
  useEffect(()=>{
    const escape=(event:KeyboardEvent)=>{
      if(event.key!=='Escape'||event.defaultPrevented||document.querySelector('dialog[open]'))return;
      const disclosure=document.activeElement?.closest('details[open]');
      if(disclosure){disclosure.removeAttribute('open');(disclosure.querySelector('summary') as HTMLElement)?.focus()}
      else if(drawer)setDrawer(false);
      else if(state.compact)command('minimize');
      else return;
      event.preventDefault();event.stopPropagation();
    };
    window.addEventListener('keydown',escape);
    return()=>window.removeEventListener('keydown',escape);
  },[drawer,state.compact]);
  useEffect(()=>{
    for(const [key,value] of Object.entries(state.theme||{})) {
      if(/^#[0-9a-fA-F]{6}$/.test(value))document.documentElement.style.setProperty('--'+key,value);
    }
  },[state.theme]);
  useEffect(()=>{
    window.pulseReceive=next=>{
      if(shouldSyncDraft(received.current,session.current,nativeDraft.current,next)){setDraft(next.draft||'');nativeDraft.current=next.draftRevision;following.current=true;setAtBottom(true)}
      received.current=true;session.current=next.sessionId;setState(next);
    };
    let latest=initial;window.pulsePatch=patch=>{latest=applyPatch(latest,patch);window.pulseReceive?.(latest)};
    command('ready');return()=>{delete window.pulseReceive;delete window.pulsePatch};
  },[]);
  const items = useMemo(()=>{const latest=state.items.findLast(i=>i.kind==='answer')?.id;return state.items.map(i=>i.kind==='answer'&&i.id===latest&&state.state==='running'?{...i,isRunning:true}:i)},[state.items,state.state]);
  const working=state.busy && state.state!=='starting';
  return <><div className={`workspace ${state.largerText?'larger':''} ${state.compact?'compact-chat':''}`}>
    {state.page!=='conversation'?<FeaturePage state={{...state,status:state.workspaceStatus||state.status}}/>:<>
    <main className="main" inert={!!state.compact&&drawer}><header className="header"><div className="identity"><div><h1>{state.sessions.find(s=>s.sessionId===state.sessionId)?.name||'Ask Pulse'}</h1></div></div><div className="header-actions"><button className="model-picker" onClick={()=>command('settings')} aria-label="Provider and model settings" title={state.model||'Choose a model'}><span className={`status-dot ${state.ready?'connected':''}`}/><SlidersHorizontal size={16}/></button><button aria-label={drawer?'Hide evidence panel':'Show evidence panel'} aria-pressed={drawer} onClick={()=>setDrawer(!drawer)}><PanelRight size={18}/></button></div></header>
      {!state.ready && state.state!=='starting' ? <section className="setup"><span className="hero-icon"><Activity size={35}/></span><h2>Your Mac. Your model.</h2><p>Connect an AI provider or a local model to ask about performance, storage and the apps you use.</p><button autoFocus className="primary" onClick={()=>command('settings')}>Connect a model <ChevronRight size={16}/></button><button className="quiet" onClick={()=>command('reconnect')}><RotateCcw size={14}/>Check setup again</button><small>Your selected provider receives your questions, a cached performance snapshot and requested diagnostic results. Provider charges may apply.</small></section>:
      <div className="thread"><div className="viewport" ref={viewport} onWheel={()=>{following.current=false}} onPointerDown={()=>{following.current=false}} onKeyDown={e=>{if(['PageUp','PageDown','Home','End','ArrowUp','ArrowDown'].includes(e.key))following.current=false}} onScroll={e=>{if(!following.current){const node=e.currentTarget;const near=node.scrollHeight-node.scrollTop-node.clientHeight<80;following.current=near;setAtBottom(near)}}}><div className="transcript">{!items.length && <section className="welcome"><span className="hero-icon"><Activity size={35}/></span><p className="eyebrow">ASK. INVESTIGATE. UNDERSTAND.</p><h2>{state.compact?'How can Pulse help?':'What’s on your mind?'}</h2><p className="welcome-detail">{state.compact?'Understand your Mac and choose a next step.':<>A slow afternoon. A full disk. An app that won’t settle.<br/>Let’s find out what your Mac is telling us.</>}</p><div className="suggestions">{(state.compact?homeSuggestions:suggestions).map(s=><button key={s.title} disabled={!state.ready||state.busy||!!draft.trim()} title={draft.trim()?'Send or clear your draft before choosing a starter':undefined} onClick={()=>{if(!draft.trim()&&state.ready&&!state.busy)command('send',{text:s.title})}}><s.icon size={19}/><strong>{s.title}</strong><span>{s.detail}</span><ChevronRight className="suggestion-arrow" size={15}/></button>)}</div><div className="evidence-note"><ShieldCheck size={14}/>Evidence first. You approve every change.</div></section>}
        {state.hasEarlier && <button className="history-more quiet" disabled={state.busy} onClick={()=>command('older')}>Load earlier messages</button>}
        {state.compact&&items.length>0&&<p className="compact-session">Continuing conversation{state.sessions.find(s=>s.sessionId===state.sessionId)?.name?`: ${state.sessions.find(s=>s.sessionId===state.sessionId)?.name}`:''}</p>}<Transcript items={items}/>
      </div>{!atBottom&&<button className="jump" aria-label="Jump to latest" onClick={()=>{following.current=true;setAtBottom(true)}}><ArrowDown size={15}/>Latest</button>}</div>
      <div className="composer-area">{(state.busy||state.voiceStatus||state.workspaceStatus||state.state==='failed'||state.state==='cancelled')&&<div className="run-status" role="status"><span className={`status-dot ${working?'connected':''}`}/>{state.busy?state.status:state.voiceStatus||state.workspaceStatus||state.status}{state.state==='failed'&&<button onClick={()=>command('reconnect')}>Reconnect</button>}</div>}
        <form className="composer" onSubmit={e=>{e.preventDefault();send()}}><textarea ref={composer} placeholder="Ask about your Mac…" aria-label="Question for Pulse" rows={2} value={draft} maxLength={12000} onChange={e=>{setDraft(e.target.value);command('draft',{text:e.target.value})}} onKeyDown={e=>{if(e.key==='Enter'&&!e.shiftKey&&!e.nativeEvent.isComposing){e.preventDefault();send()}}}/><div className="composer-controls"><details className="composer-more"><summary>More</summary><div className="composer-more-actions"><button type="button" className="composer-icon" aria-label="Attach text file" disabled={state.busy} onClick={()=>command('attach')}><Paperclip size={17}/>Attach text file</button><button type="button" className={`composer-icon ${state.voiceRecording?'recording':''}`} aria-label={state.voiceRecording?'Stop dictation':'Dictate on this Mac'} disabled={state.busy} onClick={()=>command('voice')}><Mic size={17}/>{state.voiceRecording?'Stop dictation':'Dictate'}</button><button type="button" onClick={()=>setDrawer(true)}><PanelRight size={17}/>Evidence</button><button type="button" onClick={()=>command('settings')}><SlidersHorizontal size={17}/>Provider settings</button></div></details><label className="composer-hint"><ShieldCheck size={13}/><select aria-label="Agent mode" disabled={state.busy} value={state.readOnly?'investigate':'interactive'} onChange={e=>command('mode',{readOnly:e.target.value==='investigate'})}><option value="interactive">Ask before changes</option><option value="investigate">Investigate · read only</option></select></label><UsageDetails usage={state.usage}/>{state.state === 'starting' ? <button className="send" disabled aria-label="Starting local agent"><Activity size={20}/></button> : state.busy ? <button type="button" className="send" aria-label="Stop run" onClick={()=>command('stop')}><CircleStop size={20}/></button>:<button className="send" aria-label="Send question" disabled={!draft.trim()||!state.ready||new TextEncoder().encode(draft).length>12000}><ArrowUp size={19}/></button>}</div></form>
        <p className="composer-footnote">Pulse can make mistakes. Check the evidence before approving an action.</p>{state.compact&&<details className="provider-disclosure"><summary>Uses {state.providerLabel||'your selected AI provider'}</summary><p>Your selected provider receives your questions, cached Mac readings, and requested diagnostic results. Provider charges may apply.</p></details>}</div></div>}
    </main>
    {drawer&&<aside className="evidence-drawer"><header><h2>Investigation</h2><button ref={drawerClose} aria-label="Close evidence panel" onClick={()=>setDrawer(false)}><X size={17}/></button></header><section><h3><ListChecks size={15}/>Plan and progress</h3>{state.tasks.length?state.tasks.map((task,index)=><div className="drawer-task" key={index}><span aria-hidden="true">{task.status==='completed'?'✓':task.status==='running'?'•':'○'}</span><span>{task.title}<small>{task.status}</small></span></div>):<p>When Pulse breaks work into steps, follow progress here.</p>}</section><section><h3><ShieldCheck size={15}/>Evidence</h3>{items.filter(i=>i.kind==='tool').length?items.filter(i=>i.kind==='tool').slice(-16).map(item=><details key={item.id}><summary>{item.title}<small>{item.isRunning?'Running':item.outcome==='ok'?'Complete':item.outcome||'Result'}</small></summary><pre>{item.detail}</pre></details>):<p>Native readings and action receipts appear as Pulse investigates.</p>}</section><section><h3>Take it with you</h3><button disabled={!items.some(i=>i.kind==='answer')} onClick={()=>command('export')}><Download size={15}/>Export latest answer</button><p>Save a Markdown report on this Mac.</p></section></aside>}
    </>}
  </div></>;
}
createRoot(document.getElementById('root')!).render(<App/>);

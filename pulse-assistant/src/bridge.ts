export type Usage = {context?: {estimatedTokens:number;limit:number;outputReserve:number;purpose:string;model:string;measuredAt:number;categories:{label:string;tokens:number}[];reportedTokens?:number}|null;totals:{input:number;output:number;cacheRead:number;cacheWrite:number;totalTokens:number;requests:number;missingUsage:number;missingCost:number;costUSD:string|null;compactionTokens:number};historical:boolean};
export type Item = { id: string; kind: 'user'|'answer'|'tool'|'approval'|'progress'|'error'; title: string; detail: string; isRunning: boolean; approvalID?: string; outcome?: string; interaction?: 'action'|'question'|'plan'; options?: string[] };
export type Memory = { id: string; content: string; evidence: string; kind: string; created_at: number; revision?:number; source_session?:string };
export type Session = {sessionId:string;name:string;pinned?:boolean;archived?:boolean};
export type Automation = {id:string;title:string;instructions:string;schedule:{repeatRule:string;hour:number;minute:number;weekday:number;timezoneID:string;onceAt?:string};enabled:boolean;notifyOnCompletion:boolean;nextRun?:string;lastStatus?:string;runCount:number};
export type AutomationRun = {id:string;automationID:string;sessionID:string;title:string;status:string;startedAt:string;finishedAt?:string;summary:string};
export type Snapshot = { usage: Usage|null; items: Item[]; sessions: Session[]; sessionId?: string; status: string; busy: boolean; ready: boolean; state: string; model: string; provider: string; memories: Memory[]; memoryEnabled: boolean; memoryStatus: string; largerText: boolean; hasEarlier: boolean; draft: string; draftRevision:number; readOnly: boolean; page:string; instructions:string; workspaceStatus:string; searchQuery:string; searchArchived:boolean; searchResults:Session[]; automations:Automation[]; automationRuns:AutomationRun[]; automationStatus:string; tasks:{title:string;status:string}[]; specialist:string; theme:Record<string,string>;voiceRecording:boolean;voiceStatus:string;memoryUndoID?:string };
export const initial: Snapshot = { usage: null, items: [], sessions: [], status: 'Ready when you are', busy: false, ready: false, state: 'idle', model: '', provider: '', memories: [], memoryEnabled: true, memoryStatus: '', largerText: false, hasEarlier: false, draft: '', draftRevision:0, readOnly: false, page:'conversation', instructions:'',workspaceStatus:'',searchQuery:'',searchArchived:false,searchResults:[],automations:[],automationRuns:[],automationStatus:'',tasks:[],specialist:'general',theme:{},voiceRecording:false,voiceStatus:'' };
export type Patch = { state?: Snapshot|null; items: Item[]; order?: string[]|null };
export function applyPatch(previous: Snapshot, patch: Patch): Snapshot {
  const items = new Map(previous.items.map(item=>[item.id,item]));
  for(const item of patch.items)items.set(item.id,item);
  const order=patch.order||previous.items.map(item=>item.id);
  return {...(patch.state||previous),items:order.flatMap(id=>items.has(id)?[items.get(id)!]:[])};
}
declare global { interface Window { pulseReceive?: (state: Snapshot) => void; pulsePatch?: (patch: Patch) => void; webkit?: { messageHandlers: { pulse: { postMessage: (message: unknown) => void } } } } }
export function command(action: string, fields: Record<string, unknown> = {}) {
  window.webkit?.messageHandlers.pulse.postMessage({ version: 1, action, ...fields });
}

export function shouldSyncDraft(received:boolean,session:string|undefined,revision:number,next:Snapshot) {
  return !received||session!==next.sessionId||revision!==next.draftRevision;
}

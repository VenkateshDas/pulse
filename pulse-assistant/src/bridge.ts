export type Item = { id: string; kind: 'user'|'answer'|'tool'|'approval'|'progress'|'error'; title: string; detail: string; isRunning: boolean; approvalID?: string; outcome?: string; interaction?: 'action'|'question'|'plan'; options?: string[] };
export type Memory = { id: string; content: string; evidence: string; kind: string; created_at: number };
export type Snapshot = { items: Item[]; sessions: {sessionId: string; name: string}[]; sessionId?: string; status: string; busy: boolean; ready: boolean; state: string; model: string; provider: string; memories: Memory[]; memoryEnabled: boolean; memoryStatus: string; largerText: boolean; hasEarlier: boolean; draft: string; readOnly: boolean };
export const initial: Snapshot = { items: [], sessions: [], status: 'Ready when you are', busy: false, ready: false, state: 'idle', model: '', provider: '', memories: [], memoryEnabled: true, memoryStatus: '', largerText: false, hasEarlier: false, draft: '', readOnly: false };
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

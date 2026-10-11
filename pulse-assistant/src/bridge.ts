export type Item = { id: string; kind: 'user'|'answer'|'tool'|'approval'|'progress'|'error'; title: string; detail: string; isRunning: boolean; approvalID?: string };
export type Memory = { id: string; content: string; evidence: string; kind: string; created_at: number };
export type Snapshot = { items: Item[]; sessions: {sessionId: string; name: string}[]; sessionId?: string; status: string; busy: boolean; ready: boolean; state: string; model: string; provider: string; memories: Memory[]; memoryEnabled: boolean; memoryStatus: string; largerText: boolean; hasEarlier: boolean };
export const initial: Snapshot = { items: [], sessions: [], status: 'Ready when you are', busy: false, ready: false, state: 'idle', model: '', provider: '', memories: [], memoryEnabled: true, memoryStatus: '', largerText: false, hasEarlier: false };
declare global { interface Window { pulseReceive?: (state: Snapshot) => void; webkit?: { messageHandlers: { pulse: { postMessage: (message: unknown) => void } } } } }
export function command(action: string, fields: Record<string, unknown> = {}) {
  window.webkit?.messageHandlers.pulse.postMessage({ version: 1, action, ...fields });
}

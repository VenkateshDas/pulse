// Adapted from OpenWorker Transcript.tsx (MIT, pinned source in OPENWORKER-LICENSE).
// Keep final answers outside collapsed work groups; human decisions always stay visible.
import type { Item } from './bridge';
export type Row = {kind:'activity'; id:string; items:Item[]} | {kind:'message'; id:string; item:Item};
export function groupTimeline(items: Item[]): Row[] {
  const rows: Row[] = [];
  for (const item of items) {
    if (item.kind === 'tool' || item.kind === 'progress') {
      const last = rows.at(-1);
      if (last?.kind === 'activity') last.items.push(item);
      else rows.push({kind:'activity', id:item.id, items:[item]});
    } else rows.push({kind:'message', id:item.id, item});
  }
  return rows;
}

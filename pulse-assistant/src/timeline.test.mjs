import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import ts from 'typescript';
const source=await readFile(new URL('./timeline.ts',import.meta.url),'utf8');
const js=ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2023,module:ts.ModuleKind.ESNext}}).outputText;
const {groupTimeline}=await import('data:text/javascript;base64,'+Buffer.from(js).toString('base64'));
const item=(id,kind)=>({id,kind,title:id,detail:id,isRunning:false});
test('work groups collapse narration/tools while answers and consent stay visible',()=>{
  const result=groupTimeline([item('u','user'),item('n','progress'),item('t','tool'),item('a','approval'),item('t2','tool'),item('f','answer')]);
  assert.deepEqual(result.map(row=>row.kind),['message','activity','message','activity','message']);
  assert.deepEqual(result[1].items.map(i=>i.id),['n','t']);
  assert.equal(result[2].item.kind,'approval');assert.equal(result.at(-1).item.kind,'answer');
});
test('grouping preserves stable identities and never mutates source',()=>{
  const input=[item('1','tool'),item('2','tool')];
  const first=groupTimeline(input);const later=groupTimeline([...input,item('3','tool')]);
  assert.equal(first[0].id,later[0].id);assert.equal(first[0].items.length,2);assert.equal(input.length,2);
});
const bridgeSource=await readFile(new URL('./bridge.ts',import.meta.url),'utf8');
const bridgeJS=ts.transpileModule(bridgeSource,{compilerOptions:{target:ts.ScriptTarget.ES2023,module:ts.ModuleKind.ESNext}}).outputText;
const {applyPatch,initial,shouldSyncDraft}=await import('data:text/javascript;base64,'+Buffer.from(bridgeJS).toString('base64'));
test('stream patch retains old row references, updates one answer, removes expired rows',()=>{
  const old=item('old','answer'),live=item('live','answer');
  const state={...initial,items:[old,live]};
  const result=applyPatch(state,{items:[{...live,detail:'new token'}]});
  assert.equal(result.items[0],old);assert.equal(result.items[1].detail,'new token');
  const removed=applyPatch(result,{items:[],order:['live']});
  assert.equal(removed.items.length,1);assert.equal(removed.items[0].id,'live');
});

test('delayed typing echoes cannot replace newer local draft; intentional native edits sync',()=>{
  const echo={...initial,sessionId:'chat',draft:'a',draftRevision:0};
  assert.equal(shouldSyncDraft(true,'chat',0,echo),false);
  assert.equal(shouldSyncDraft(true,'chat',0,{...echo,draft:'attached text',draftRevision:1}),true);
  assert.equal(shouldSyncDraft(true,'other',0,echo),true);
  assert.equal(shouldSyncDraft(false,undefined,0,initial),true);
});

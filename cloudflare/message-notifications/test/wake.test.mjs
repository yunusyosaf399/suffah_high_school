import {test} from 'node:test';
import assert from 'node:assert/strict';
import worker,{available,blocked} from '../src/index.js';
test('lease prevents concurrent dispatch and expires',()=>{
  const now=Date.now();
  assert.equal(available({fields:{pushPending:{booleanValue:true}}},now),true);
  assert.equal(available({fields:{pushPending:{booleanValue:true},pushLeaseUntil:{timestampValue:new Date(now+90000).toISOString()}}},now),false);
  assert.equal(available({fields:{pushPending:{booleanValue:true},pushLeaseUntil:{timestampValue:new Date(now-1).toISOString()}}},now),true);
  assert.equal(available({fields:{pushPending:{booleanValue:false}}},now),false);
});
test('wake rejects unauthenticated requests before accessing admin credentials',async()=>{
  const response=await worker.fetch(new Request('https://example.test/v1/wake?thread=abc&message=def',{method:'POST'}),{},{});
  assert.equal(response.status,403);
});
test('wake rejects invalid IDs and unsupported routes',async()=>{
  assert.equal((await worker.fetch(new Request('https://example.test/v1/wake?thread=a%2Fb&message=def',{method:'POST'}),{},{})).status,400);
  assert.equal((await worker.fetch(new Request('https://example.test/'),{},{})).status,404);
});

test('owner conversation cleanup blocks only its requested scope',()=>{
  const job=(scope,thread,status)=>({fields:{scope:{stringValue:scope},threadUid:{stringValue:thread},status:{stringValue:status}}});
  assert.equal(blocked(null,'abc'),false);
  assert.equal(blocked(job('all','','queued'),'abc'),true);
  assert.equal(blocked(job('all','','done'),'abc'),false);
  assert.equal(blocked(job('thread','abc','running'),'abc'),true);
  assert.equal(blocked(job('thread','abc','running'),'def'),false);
});

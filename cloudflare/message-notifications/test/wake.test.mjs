import {test} from 'node:test';
import assert from 'node:assert/strict';
import worker,{available,blocked,cleanupThreadBatch} from '../src/index.js';
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

test('cleanup endpoint rejects unauthenticated requests',async()=>{
  const response=await worker.fetch(new Request('https://example.test/v1/cleanup',{method:'POST'}),{},{});
  assert.equal(response.status,403);
});
test('cleanup groups all chat record types into one commit and verifies empty before removing root',async(t)=>{
  const root='projects/test/databases/(default)/documents/';
  const thread='participant',prefix='portal_threads/'+thread;
  const mk=path=>({name:root+path});
  let empty=false;
  const commits=[],audioDeletes=[];
  t.mock.method(globalThis,'fetch',async(url,opts={})=>{
    const target=String(url);
    if(target.endsWith(':runQuery')){
      const q=JSON.parse(opts.body).structuredQuery;
      assert.equal(q.where.fieldFilter.value.stringValue,thread);
      const collection=q.from[0].collectionId;
      return Response.json(empty?[]:[{document:mk(collection+'/record')}]);
    }
    if(target.endsWith(':commit')){
      commits.push(JSON.parse(opts.body).writes.map(w=>w.delete));
      return Response.json({});
    }
    const path=new URL(target).pathname;
    const collection=path.split('/').pop();
    let documents=[];
    if(!empty){
      if(collection==='messages'||collection==='scheduled')documents=[mk(prefix+'/'+collection+'/record')];
      if(collection==='hidden')documents=[mk(prefix+'/hidden/viewer')];
      if(collection==='items')documents=[mk(prefix+'/hidden/viewer/items/record')];
    }
    return Response.json({documents});
  });
  const env={FIREBASE_PROJECT_ID:'test',VOICE_FILES:{
    list:async({prefix})=>{assert.equal(prefix,'voice-messages/participant/');return {objects:empty?[]:[{key:prefix+'record.m4a'}],truncated:false};},
    delete:async(keys)=>audioDeletes.push(keys)
  }};
  assert.deepEqual(await cleanupThreadBatch(env,'token',thread),{done:false,removed:5});
  assert.equal(commits.length,1);
  assert.equal(commits[0].length,5);
  assert.ok(commits[0].every(x=>x.startsWith(root+prefix+'/')||x.startsWith(root+'voice_jobs/')||x.startsWith(root+'message_alerts/')));
  assert.deepEqual(audioDeletes,[['voice-messages/participant/record.m4a']]);
  empty=true;
  assert.deepEqual(await cleanupThreadBatch(env,'token',thread),{done:true,removed:1});
  assert.deepEqual(commits[1],[root+prefix]);
});

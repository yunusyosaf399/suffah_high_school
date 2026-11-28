import {test} from 'node:test';
import assert from 'node:assert/strict';
import worker,{available,blocked,cleanupThreadBatch,callOutcome,messagePush} from '../src/index.js';
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
  assert.deepEqual(await cleanupThreadBatch(env,'token',thread),{done:false,removed:6});
  assert.equal(commits.length,1);
  assert.equal(commits[0].length,6);
  assert.ok(commits[0].every(x=>x.startsWith(root+prefix+'/')||x.startsWith(root+'voice_jobs/')||x.startsWith(root+'message_alerts/')||x.startsWith(root+'office_calls_v2/')));
  assert.deepEqual(audioDeletes,[['voice-messages/participant/record.m4a']]);
  empty=true;
  assert.deepEqual(await cleanupThreadBatch(env,'token',thread),{done:true,removed:1});
  assert.deepEqual(commits[1],[root+prefix]);
});

test('office call endpoints require authenticated school user',async()=>{
  for(const path of ['/v1/call-ice?uid=parent','/v1/call-wake?uid=parent&call=ABCDEFGHIJKLMNOPQRST']){
    assert.equal((await worker.fetch(new Request('https://example.test'+path,{method:'POST'}),{},{})).status,403);
  }
});

test('call history records completed duration or declined/missed outcome',()=>{
  const t=n=>({timestampValue:new Date(n).toISOString()});
  const end=Date.now();
  assert.deepEqual(callOutcome({status:{stringValue:'ended'},mediaConnectedAt:t(end-65000),updatedAt:t(end)}),{status:'completed',seconds:65});
  assert.deepEqual(callOutcome({status:{stringValue:'declined'},updatedAt:t(end)}),{status:'declined',seconds:0});
  assert.deepEqual(callOutcome({status:{stringValue:'ringing'},historyDueAt:t(end-1000)},end),{status:'missed',seconds:0});
});
test('two-way call endpoints reject anonymous clients',async()=>{
  for(const path of ['/v1/call-v2-wake?uid=parent&call=ABCDEFGHIJKLMNOPQRST','/v1/call-history?call=ABCDEFGHIJKLMNOPQRST']){
    assert.equal((await worker.fetch(new Request('https://example.test'+path,{method:'POST'}),{},{})).status,403);
  }
});

test('enhanced message devices receive private data-only pushes; older devices retain tray notifications',()=>{
  const legacy=messagePush({name:'push_devices/legacy',fields:{}},'u','thread','msg').message;
  const updated=messagePush({name:'push_devices/updated',fields:{notificationVersion:{integerValue:'2'}}},'u','thread','msg').message;
  assert.equal(legacy.notification.body,'You have a new school message');
  assert.equal(updated.notification,undefined);
  assert.deepEqual(updated.data,{type:'school_message',recipientUid:'u',threadUid:'thread',messageId:'msg'});
  assert.equal(updated.android.priority,'HIGH');
  assert.equal(updated.data.text,undefined);
});
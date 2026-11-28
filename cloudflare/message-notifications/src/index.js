// Immediate authenticated wake-up plus cron fallback. Recipients are never supplied by clients.
const owner='tQt6vca2zuagZipvknBwcmSRcrc2';
const S=stringValue=>({stringValue});
const B=booleanValue=>({booleanValue});
const F=(fieldPath,op,value)=>({fieldFilter:{field:{fieldPath},op,value}});

const base=env=>'https://firestore.googleapis.com/v1/projects/'+encodeURIComponent(env.FIREBASE_PROJECT_ID)+'/databases/(default)/documents';
let cached;
function b64(bytes){return btoa(String.fromCharCode(...new Uint8Array(bytes))).replace(/=/g,'').replace(/\+/g,'-').replace(/\//g,'_');}
const enc=s=>new TextEncoder().encode(s);
async function access(env){
  if(cached&&cached.exp>Date.now()+60000)return cached.token;
  const account=JSON.parse(env.FCM_SERVICE_ACCOUNT||'{}');
  if(account.project_id!==env.FIREBASE_PROJECT_ID||!account.client_email||!account.private_key)throw Error('Missing matching service account');
  const now=Math.floor(Date.now()/1000),aud='https://oauth2.googleapis.com/token';
  const claims={iss:account.client_email,scope:'https://www.googleapis.com/auth/datastore https://www.googleapis.com/auth/firebase.messaging',aud,iat:now,exp:now+3600};
  const input=b64(enc(JSON.stringify({alg:'RS256',typ:'JWT'})))+'.'+b64(enc(JSON.stringify(claims)));
  const pem=account.private_key.replace(/-----[^-]+-----/g,'').replace(/\s/g,'');
  const key=await crypto.subtle.importKey('pkcs8',Uint8Array.from(atob(pem),c=>c.charCodeAt(0)),{name:'RSASSA-PKCS1-v1_5',hash:'SHA-256'},false,['sign']);
  const assertion=input+'.'+b64(await crypto.subtle.sign('RSASSA-PKCS1-v1_5',key,enc(input)));
  const response=await fetch(aud,{method:'POST',body:new URLSearchParams({grant_type:'urn:ietf:params:oauth:grant-type:jwt-bearer',assertion}),redirect:'manual'});
  if(!response.ok)throw Error('Google OAuth failed: '+response.status);
  const data=await response.json();
  cached={token:data.access_token,exp:Date.now()+data.expires_in*1000};
  return cached.token;
}
async function request(url,token,options={}){
  const res=await fetch(url,{...options,headers:{Authorization:'Bearer '+token,'Content-Type':'application/json'},redirect:'manual'});
  if(!res.ok)throw Error('Google API status '+res.status);
  return res.status===204?null:res.json();
}
async function query(env,token,collection,where,limit,orderBy){
  const q={from:[{collectionId:collection}],where,limit,...(orderBy?{orderBy}: {})};
  const rows=await request(base(env)+':runQuery',token,{method:'POST',body:JSON.stringify({structuredQuery:q})});
  return rows.map(r=>r.document).filter(Boolean);
}
function active(d){const f=d?.fields||{};return f.active?.booleanValue===true&&f.removed?.booleanValue!==true&&f.permissions?.mapValue?.fields?.messages?.booleanValue!==false;}
function id(d){return d.name.split('/').pop();}
async function user(env,token,uid){
  try{return await request(base(env)+'/users/'+encodeURIComponent(uid),token);}
  catch(e){if(e.message==='Google API status 404')return null;throw e;}
}
async function patch(env,token,d,fields){
  const mask=Object.keys(fields).map(k=>'updateMask.fieldPaths='+encodeURIComponent(k)).join('&');
  return request(base(env)+'/message_alerts/'+encodeURIComponent(id(d))+'?'+mask+'&currentDocument.updateTime='+encodeURIComponent(d.updateTime),token,{method:'PATCH',body:JSON.stringify({fields})});
}
async function mark(env,token,d){await patch(env,token,d,{pushPending:B(false),pushLeaseUntil:{nullValue:null}});}
export function available(d,now=Date.now()){
  return d?.fields?.pushPending?.booleanValue===true &&
    !(Date.parse(d.fields.pushLeaseUntil?.timestampValue)>now);
}
async function dispatch(env,token,d){
  if(!available(d))return false;
  let claimed;
  try{
    claimed=await patch(env,token,d,{pushLeaseUntil:{timestampValue:new Date(Date.now()+90000).toISOString()}});
  }catch(e){
    // A competing HTTP or cron invocation already claimed this document.
    if(/status (409|412|400)$/.test(e.message))return false;
    throw e;
  }
  // If delivery fails, the lease expires and cron can retry.
  await deliver(env,token,claimed);
  return true;
}
async function authenticateWake(request,env,thread,alert){
  const bearer=request.headers.get('Authorization')||'';
  if(!/^Bearer [^\s]+$/.test(bearer))return false;
  // Firebase's REST API validates the ID token and applies existing message
  // security rules. A caller can only wake a message they themselves sent.
  const response=await fetch(base(env)+'/portal_threads/'+encodeURIComponent(thread)+'/messages/'+encodeURIComponent(alert),{
    headers:{Authorization:bearer},redirect:'manual'
  });
  if(!response.ok)return false;
  const message=await response.json();
  // Firestore has verified the exact bearer token. Read its signed subject.
  const jwt=bearer.slice(7);
  const part=jwt.split('.')[1];
  if(!part)return false;
  let uid;
  try{uid=JSON.parse(atob(part.replace(/-/g,'+').replace(/_/g,'/'))).sub;}catch(_){return false;}
  // The same exact JWT was accepted by Firestore above, including signature,
  // expiry and project audience; its subject is therefore authenticated.
  return typeof uid==='string'&&message.fields?.senderUid?.stringValue===uid&&message.fields?.deleted?.booleanValue!==true?uid:false;
}
async function deliver(env,token,d){
  const f=d.fields||{},thread=f.threadUid?.stringValue,sender=f.senderUid?.stringValue,fromSchool=f.fromSchool?.booleanValue;
  if(!thread||!sender||typeof fromSchool!=='boolean'||Date.now()-Date.parse(f.createdAt?.timestampValue)>86400000){await mark(env,token,d);return;}
  if(blocked(await cleanupState(env,token),thread))return;
  const participant=await user(env,token,thread);
  const role=participant?.fields?.role?.stringValue;
  if(!active(participant)||!['parent','teacher'].includes(role)){await mark(env,token,d);return;}
  const source=sender===thread?participant:await user(env,token,sender);
  if(!active(source)||(fromSchool?(sender!==owner&&source.fields.role?.stringValue!=='principal'):sender!==thread)){await mark(env,token,d);return;}
  let recipients=[thread];
  if(!fromSchool){
    const principals=await query(env,token,'users',F('role','EQUAL',S('principal')),25);
    recipients=[owner,...principals.filter(active).map(id)];
    // Check that the registered owner has not been deactivated.
    if(!active(await user(env,token,owner)))recipients=recipients.filter(x=>x!==owner);
  }
  recipients=[...new Set(recipients)].filter(x=>x!==sender);
  if(!recipients.length){await mark(env,token,d);return;}
  const devices=await query(env,token,'push_devices',F('uid','IN',{arrayValue:{values:recipients.map(S)}}),20);
  // Generic notification only, never expose private chat text on lock screens.
  for(const device of devices){
    const uid=device.fields.uid?.stringValue;
    if(!recipients.includes(uid))continue;
    const body={message:{token:id(device),notification:{title:'Suffah High School',body:'You have a new school message'},data:{type:'school_message',recipientUid:uid,threadUid:thread},android:{priority:'HIGH',notification:{tag:id(d),sound:'default'}}}};
    const response=await fetch('https://fcm.googleapis.com/v1/projects/'+encodeURIComponent(env.FIREBASE_PROJECT_ID)+'/messages:send',{method:'POST',headers:{Authorization:'Bearer '+token,'Content-Type':'application/json'},body:JSON.stringify(body),redirect:'manual'});
    if(response.ok)continue;
    const error=await response.json().catch(()=>({}));
    if(error.error?.details?.some(x=>x.errorCode==='UNREGISTERED'))continue;
    throw Error('FCM delivery status '+response.status);
  }
  await mark(env,token,d);
}
async function requestDocument(env,token,alert){
  try{return await request(base(env)+'/message_alerts/'+encodeURIComponent(alert),token);}
  catch(e){if(e.message==='Google API status 404')return null;throw e;}
}

// The bearer token must be accepted by Firestore before its subject is used.
function signedSubject(bearer){
  try {const part=bearer.slice(7).split('.')[1];return JSON.parse(atob(part.replace(/-/g,'+').replace(/_/g,'/'))).sub;}
  catch(_){return null;}
}
async function clientRead(req,env,path){
  const bearer=req.headers.get('Authorization')||'';
  if(!/^Bearer [^\s]+$/.test(bearer))return null;
  const res=await fetch(base(env)+path,{headers:{Authorization:bearer},redirect:'manual'});
  if(!res.ok)return null;
  const uid=signedSubject(bearer);
  return typeof uid==='string'&&uid?{uid,doc:await res.json()}:null;
}
const voiceKey=(thread,message)=>'voice-messages/'+thread+'/'+message+'.m4a';
async function optionalDoc(env,token,path){
  try{return await request(base(env)+path,token);}
  catch(e){if(e.message==='Google API status 404')return null;throw e;}
}
async function cleanupState(env,token){
  return optionalDoc(env,token,'/chat_cleanup/current');
}
export function blocked(job,thread){
  return !!job&&job.fields?.status?.stringValue!=='done'&&(job.fields?.scope?.stringValue==='all'||job.fields?.threadUid?.stringValue===thread);
}
async function voiceRequest(req,env,thread,message){
  const messagePath='/portal_threads/'+thread+'/messages/'+message;
  const jobPath='/voice_jobs/'+message;
  if(req.method==='GET'){
    const auth=await clientRead(req,env,messagePath);
    if(!auth||auth.doc.fields?.kind?.stringValue!=='voice'||auth.doc.fields?.deleted?.booleanValue===true)return new Response('Not found',{status:404});
    const token=await access(env),job=await optionalDoc(env,token,jobPath);
    if(!job||job.fields.ready?.booleanValue!==true||job.fields.threadUid?.stringValue!==thread||Date.parse(job.fields.expiresAt?.timestampValue)<=Date.now())return new Response('Expired',{status:404});
    const obj=await env.VOICE_FILES.get(voiceKey(thread,message));
    return obj?new Response(obj.body,{headers:{'Content-Type':'audio/mp4','Cache-Control':'private, no-store'}}):new Response('Not found',{status:404});
  }
  if(req.method!=='PUT')return new Response('Method not allowed',{status:405});
  const auth=await clientRead(req,env,'/portal_threads/'+thread);
  if(!auth)return new Response('Forbidden',{status:403});
  const token=await access(env),source=await user(env,token,auth.uid),target=await user(env,token,thread);
  if(blocked(await cleanupState(env,token),thread))return new Response('Conversation is being deleted',{status:409});
  const school=auth.uid===owner||source?.fields?.role?.stringValue==='principal';
  if(!active(source)||!active(target)||!['parent','teacher'].includes(target.fields.role?.stringValue)||(!school&&auth.uid!==thread))return new Response('Forbidden',{status:403});
  if(req.headers.get('Content-Type')!=='audio/mp4')return new Response('Invalid audio',{status:415});
  // Stream with a hard cap rather than accepting an unbounded body.
  const reader=req.body?.getReader();if(!reader)return new Response('Empty audio',{status:400});
  let size=0;const chunks=[];
  while(true){const {done,value}=await reader.read();if(done)break;size+=value.byteLength;if(size>3000000){await reader.cancel();return new Response('Too large',{status:413});}chunks.push(value);}
  if(size<12)return new Response('Invalid audio',{status:400});
  const bytes=new Uint8Array(size);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length;}
  if(String.fromCharCode(...bytes.slice(4,8))!=='ftyp')return new Response('Invalid audio container',{status:415});
  if(await optionalDoc(env,token,messagePath)||await optionalDoc(env,token,'/message_alerts/'+message))return new Response('Message already exists',{status:409});
  const settings=await optionalDoc(env,token,'/voice_settings/global');
  const mode=['played','7days','14days'].includes(settings?.fields?.mode?.stringValue)?settings.fields.mode.stringValue:'played';
  const now=Date.now(),expires=now+(mode==='7days'?7:14)*86400000;
  // Register before storing audio, so even a failed/abandoned upload is swept.
  // The unique message ID cannot overwrite an existing upload.
  const job=await request(base(env)+'/voice_jobs?documentId='+encodeURIComponent(message),token,{method:'POST',body:JSON.stringify({fields:{
    threadUid:S(thread),senderUid:S(auth.uid),mode:S(mode),ready:B(false),expiresAt:{timestampValue:new Date(now+600000).toISOString()},
    createdAt:{timestampValue:new Date(now).toISOString()}
  }})});
  await env.VOICE_FILES.put(voiceKey(thread,message),bytes,{httpMetadata:{contentType:'audio/mp4'}});
  try{if(blocked(await cleanupState(env,token),thread))throw Error('Conversation cleanup in progress');
  await request(base(env)+jobPath+'?updateMask.fieldPaths=ready&updateMask.fieldPaths=expiresAt&currentDocument.updateTime='+encodeURIComponent(job.updateTime),token,{method:'PATCH',body:JSON.stringify({fields:{ready:B(true),expiresAt:{timestampValue:new Date(expires).toISOString()}}})});
  }catch(e){await env.VOICE_FILES.delete(voiceKey(thread,message));throw e;}
  return new Response(null,{status:201});
}
async function purgeVoice(env,token,job){
  const thread=job.fields.threadUid?.stringValue,message=id(job);
  if(!/^[A-Za-z0-9_-]{1,128}$/.test(thread||'')||! /^[A-Za-z0-9_-]{1,128}$/.test(message))throw Error('Invalid voice job');
  // Object deletion is idempotent. Keep the job if any operation fails.
  await env.VOICE_FILES.delete(voiceKey(thread,message));
  const prefix='projects/'+env.FIREBASE_PROJECT_ID+'/databases/(default)/documents/';
  const messagePath='portal_threads/'+thread+'/messages/'+message;
  const alertPath='message_alerts/'+message;
  const m=await optionalDoc(env,token,'/'+messagePath);
  const a=await optionalDoc(env,token,'/'+alertPath);
  const sender=job.fields.senderUid?.stringValue;
  const isVoice=m?.fields?.senderUid?.stringValue===sender&&(m?.fields?.kind?.stringValue==='voice'||m?.fields?.voiceRetracted?.booleanValue===true);
  const writes=[{delete:prefix+'voice_jobs/'+message,currentDocument:{updateTime:job.updateTime}}];
  if(isVoice){
    writes.push({delete:prefix+messagePath,currentDocument:{updateTime:m.updateTime}});
    if(a?.fields?.threadUid?.stringValue===thread&&a?.fields?.senderUid?.stringValue===sender)
      writes.push({delete:prefix+alertPath,currentDocument:{updateTime:a.updateTime}});
  }
  await request(base(env)+':commit',token,{method:'POST',body:JSON.stringify({writes})});
}
async function cleanupVoice(env,token){
  const due=await query(env,token,'voice_jobs',F('expiresAt','LESS_THAN_OR_EQUAL',{timestampValue:new Date().toISOString()}),5,[{field:{fieldPath:'expiresAt'},direction:'ASCENDING'}]);
  for(const job of due)await purgeVoice(env,token,job);
}


// Owner creates one durable cleanup request. Server processes bounded batches;
// the write freeze prevents new messages being mixed into the deletion.
const rootName=env=>'projects/'+env.FIREBASE_PROJECT_ID+'/databases/(default)/documents/';
async function listDocs(env,token,path,limit=12){
  const data=await request(base(env)+'/'+path+'?pageSize='+limit+'&showMissing=true'+(path==='voice_jobs'?'':'&mask.fieldPaths=createdAt'),token);
  return data.documents||[];
}
async function deleteDocs(env,token,names){
  if(names.length)await request(base(env)+':commit',token,{method:'POST',body:JSON.stringify({writes:names.map(name=>({delete:name}))})});
}
async function updateCleanup(env,token,job,fields){
  const mask=Object.keys(fields).map(k=>'updateMask.fieldPaths='+encodeURIComponent(k)).join('&');
  return request(base(env)+'/chat_cleanup/current?'+mask+'&currentDocument.updateTime='+encodeURIComponent(job.updateTime),token,{method:'PATCH',body:JSON.stringify({fields})});
}
async function deleteVoiceJobs(env,token,jobs){
  const keys=jobs.map(j=>voiceKey(j.fields.threadUid.stringValue,id(j)));
  if(keys.length)await env.VOICE_FILES.delete(keys);
  await deleteDocs(env,token,jobs.map(j=>j.name));
}
// Fetch independent collections together, then delete them in one Firestore
// commit. A second pass verifies that nothing remains before removing a root.
const CLEANUP_BATCH=40;
async function cleanupThreadBatch(env,token,thread){
  if(!/^[A-Za-z0-9_-]{1,128}$/.test(thread))throw Error('Invalid cleanup thread');
  const path='portal_threads/'+thread;
  const [jobs,msgs,scheduled,alerts,viewers,objects]=await Promise.all([
    query(env,token,'voice_jobs',F('threadUid','EQUAL',S(thread)),CLEANUP_BATCH),
    listDocs(env,token,path+'/messages',CLEANUP_BATCH),
    listDocs(env,token,path+'/scheduled',CLEANUP_BATCH),
    query(env,token,'message_alerts',F('threadUid','EQUAL',S(thread)),CLEANUP_BATCH),
    listDocs(env,token,path+'/hidden',1),
    env.VOICE_FILES.list({prefix:'voice-messages/'+thread+'/',limit:100}),
  ]);
  const names=[...jobs,...msgs,...scheduled,...alerts].map(d=>d.name);
  if(viewers.length){
    const items=await listDocs(env,token,path+'/hidden/'+id(viewers[0])+'/items',CLEANUP_BATCH);
    names.push(...(items.length?items.map(d=>d.name):[viewers[0].name]));
  }
  const keys=[...new Set([...jobs.map(j=>voiceKey(thread,id(j))),...objects.objects.map(o=>o.key)])];
  if(keys.length)await env.VOICE_FILES.delete(keys);
  if(names.length||keys.length){
    await deleteDocs(env,token,names);
    return {done:false,removed:names.length};
  }
  if(objects.truncated)throw Error('Incomplete audio listing');
  await deleteDocs(env,token,[rootName(env)+path]);
  return {done:true,removed:1};
}
async function runChatCleanup(env,token){
  let job=await cleanupState(env,token);
  if(!job||job.fields?.status?.stringValue==='done')return false;
  if(Date.parse(job.fields?.leaseUntil?.timestampValue)>Date.now())return true;
  try{job=await updateCleanup(env,token,job,{status:S('running'),leaseUntil:{timestampValue:new Date(Date.now()+90000).toISOString()}});}
  catch(e){if(/status (409|412)$/.test(e.message))return true;throw e;}
  const all=job.fields.scope.stringValue==='all';
  let complete=false,removed=Number(job.fields.deletedRecords?.integerValue||0);
  try{
    // Three grouped passes stay within the Worker subrequest budget.
    for(let step=0;step<3;step++){
      const thread=all?idOrNull((await listDocs(env,token,'portal_threads',1))[0]):job.fields.threadUid.stringValue;
      if(!thread){
        const [jobs,alerts,objects]=await Promise.all([
          listDocs(env,token,'voice_jobs',CLEANUP_BATCH),
          listDocs(env,token,'message_alerts',CLEANUP_BATCH),
          env.VOICE_FILES.list({prefix:'voice-messages/',limit:100}),
        ]);
        const keys=[...new Set([...jobs.map(j=>voiceKey(j.fields.threadUid.stringValue,id(j))),...objects.objects.map(o=>o.key)])];
        if(keys.length)await env.VOICE_FILES.delete(keys);
        const names=[...jobs,...alerts].map(d=>d.name);
        await deleteDocs(env,token,names);
        removed+=names.length;
        if(!names.length&&!keys.length&&!objects.truncated){complete=true;break;}
        continue;
      }
      const result=await cleanupThreadBatch(env,token,thread);
      removed+=result.removed;
      if(result.done&&!all){complete=true;break;}
    }
    await updateCleanup(env,token,job,{status:S(complete?'done':'running'),deletedRecords:{integerValue:String(removed)},lastError:{nullValue:null},leaseUntil:{nullValue:null},...(complete?{completedAt:{timestampValue:new Date().toISOString()}}:{})});
  }catch(e){
    // Keep the request durable, expose a safe error code, and release the lease
    // only if this invocation still owns it. Never unlock writes on failure.
    const code=/Google API status \d+/.exec(e.message)?.[0]||'Cleanup operation failed';
    try{await updateCleanup(env,token,job,{status:S('running'),deletedRecords:{integerValue:String(removed)},lastError:S(code),leaseUntil:{nullValue:null}});}catch(_){}
    throw e;
  }
  return true;
}
function idOrNull(d){return d?id(d):null;}

export default {
  async fetch(request,env,ctx){
    const url=new URL(request.url);
    if(url.pathname==='/v1/cleanup'){
      if(request.method!=='POST')return new Response('Method not allowed',{status:405});
      try{
        // Firestore independently verifies this is the pinned owner.
        const auth=await clientRead(request,env,'/chat_cleanup/current');
        if(!auth||auth.uid!==owner)return new Response('Forbidden',{status:403});
        await runChatCleanup(env,await access(env));
        return new Response(null,{status:204});
      }catch(e){console.error('Conversation cleanup failed',e.message);return new Response('Cleanup retry needed',{status:503});}
    }
    if(url.pathname!=='/v1/voice'&&(request.method!=='POST'||url.pathname!=='/v1/wake'))return new Response('Not found',{status:404});
    const thread=url.searchParams.get('thread')||'',alert=url.searchParams.get('message')||'';
    if(!/^[A-Za-z0-9_-]{1,128}$/.test(thread)||! /^[A-Za-z0-9_-]{1,128}$/.test(alert))return new Response('Invalid request',{status:400});
    try{
      if(url.pathname==='/v1/voice')return await voiceRequest(request,env,thread,alert);
      const uid=await authenticateWake(request,env,thread,alert);
      if(!uid)return new Response('Forbidden',{status:403});
      const token=await access(env);
      const d=await requestDocument(env,token,alert);
      if(!d||d.fields?.threadUid?.stringValue!==thread||d.fields?.senderUid?.stringValue!==uid)return new Response('Forbidden',{status:403});
      if(available(d))ctx.waitUntil(dispatch(env,token,d).catch(e=>console.error('Immediate push failed',e.message)));
      return new Response(null,{status:202});
    }catch(e){console.error('Wake request failed',e.message);return new Response('Retry via queue',{status:503});}
  },
  async scheduled(_event,env){
    try{if(await runChatCleanup(env,await access(env)))return;}catch(e){console.error('Conversation cleanup failed',e.message);return;}
    try{
      const token=await access(env);
      // Skip leased events without blocking the next available queued event.
      const jobs=await query(env,token,'message_alerts',F('pushPending','EQUAL',B(true)),10,[{field:{fieldPath:'createdAt'},direction:'ASCENDING'}]);
      const job=jobs.find(d=>available(d));
      if(job)await dispatch(env,token,job);
    }catch(e){console.error('Message push processing failed',e.message);}
    try{await cleanupVoice(env,await access(env));}catch(e){console.error('Voice cleanup failed',e.message);}
  },
};

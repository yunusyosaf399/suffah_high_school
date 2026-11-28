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
export default {
  async fetch(request,env,ctx){
    const url=new URL(request.url);
    if(request.method!=='POST'||url.pathname!=='/v1/wake')return new Response('Not found',{status:404});
    const thread=url.searchParams.get('thread')||'',alert=url.searchParams.get('message')||'';
    if(!/^[A-Za-z0-9_-]{1,128}$/.test(thread)||! /^[A-Za-z0-9_-]{1,128}$/.test(alert))return new Response('Invalid request',{status:400});
    try{
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
    try{
      const token=await access(env);
      // Skip leased events without blocking the next available queued event.
      const jobs=await query(env,token,'message_alerts',F('pushPending','EQUAL',B(true)),10,[{field:{fieldPath:'createdAt'},direction:'ASCENDING'}]);
      const job=jobs.find(d=>available(d));
      if(job)await dispatch(env,token,job);
    }catch(e){console.error('Message push processing failed',e.message);}
  },
};

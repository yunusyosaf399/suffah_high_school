// No public send endpoint: only the Cloudflare cron trigger may dispatch.
const owner='tQt6vca2zuagZipvknBwcmSRcrc2';
const S=stringValue=>({stringValue});
const B=booleanValue=>({booleanValue});
const F=(fieldPath,op,value)=>({fieldFilter:{field:{fieldPath},op,value}});
const AND=(...filters)=>({compositeFilter:{op:'AND',filters}});
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
  const response=await fetch(aud,{method:'POST',body:new URLSearchParams({grant_type:'urn:ietf:params:oauth:grant-type:jwt-bearer',assertion}),redirect:'error'});
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
async function mark(env,token,d){
  await request(base(env)+'/message_alerts/'+encodeURIComponent(id(d))+'?updateMask.fieldPaths=pushPending&currentDocument.updateTime='+encodeURIComponent(d.updateTime),token,{method:'PATCH',body:JSON.stringify({fields:{pushPending:B(false)}})});
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
export default {
  fetch(){return new Response('Scheduled service only',{status:404});},
  async scheduled(_event,env){
    try{
      const token=await access(env);
      // One event per minute keeps subrequests bounded on the free plan.
      const jobs=await query(env,token,'message_alerts',F('pushPending','EQUAL',B(true)),1,[{field:{fieldPath:'createdAt'},direction:'ASCENDING'}]);
      for(const job of jobs)await deliver(env,token,job);
    }catch(e){console.error('Message push processing failed',e.message);}
  },
};

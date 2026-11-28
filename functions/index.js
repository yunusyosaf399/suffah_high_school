'use strict';

const {onSchedule} = require('firebase-functions/v2/scheduler');
const {logger} = require('firebase-functions');
const {initializeApp} = require('firebase-admin/app');
const {getFirestore, FieldValue} = require('firebase-admin/firestore');
const {runMonthlyScheduler} = require('./scheduler');

initializeApp();

// Runs once each morning at 06:10 Pakistan time. One Cloud Scheduler job
// serves all four types, with per-category / per-plan generation days.
exports.generateMonthlyFinance = onSchedule({
  schedule: '10 6 * * *',
  timeZone: 'Asia/Karachi',
  region: 'asia-south1',
  timeoutSeconds: 540,
  memory: '512MiB',
  maxInstances: 1,
  retryCount: 0,
}, async () => {
  const result = await runMonthlyScheduler(getFirestore(), new Date(), {
    serverTimestamp: () => FieldValue.serverTimestamp(),
    logger,
  });
  logger.info('Monthly finance scheduler completed', result);
});

const {onRequest}=require('firebase-functions/v2/https');
const {getAuth}=require('firebase-admin/auth');
const {PortalError,activeAccount,portalAction}=require('./portal');

// Native Flutter Windows and Android use HTTPS with a Firebase ID token.
// Only allowlisted fields leave this service; the Admin SDK never returns
// entire private student, staff, finance or examination records.
exports.schoolPortal=onRequest({region:'asia-south1',timeoutSeconds:120,memory:'512MiB',maxInstances:5},async(req,res)=>{
  res.set('Cache-Control','private, no-store');
  if(req.method!=='POST') {res.status(405).json({error:'POST required.'});return;}
  const match=/^Bearer ([^\s]+)$/.exec(req.get('Authorization')||'');
  if(!match) {res.status(401).json({error:'Sign in first.'});return;}
  try {
    let token;
    try {token=await getAuth().verifyIdToken(match[1],true);}
    catch(_) {res.status(401).json({error:'Sign-in expired or revoked.'});return;}
    const db=getFirestore();
    const account=activeAccount(token.uid,(await db.collection('users').doc(token.uid).get()).data());
    const body=req.body;
    if(!body || typeof body!=='object' || Array.isArray(body)) {res.status(400).json({error:'Invalid request.'});return;}
    const data=await portalAction(db,getAuth(),account,body,()=>FieldValue.serverTimestamp());
    res.json(data);
  } catch(error) {
    if(error instanceof PortalError) {res.status(error.status).json({error:error.message});return;}
    logger.error('School portal operation failed',{code:String(error.code||'unknown')});
    res.status(503).json({error:'School portal data is unavailable. Contact the administrator.'});
  }
});

 // Scheduled chat delivery uses a deterministic message ID and one transaction.
exports.deliverScheduledMessages = onSchedule({
  schedule:'every 5 minutes',region:'asia-south1',timeoutSeconds:120,maxInstances:1,
},async()=>{
  const db=getFirestore();
  const now=new Date();
  const pending=await db.collectionGroup('scheduled').where('sendAt','<=',now).limit(100).get();
  for(const item of pending.docs){
    if(item.ref.parent.parent?.parent.id!=='portal_threads') continue;
    await db.runTransaction(async tx=>{
      const fresh=await tx.get(item.ref);
      if(!fresh.exists)return;
      const d=fresh.data(),thread=item.ref.parent.parent,target=thread.id;
      if(!d.sendAt||d.sendAt.toMillis()>now.getTime())return;
      const sender=(await tx.get(db.collection('users').doc(d.senderUid))).data()||{};
      const receiver=(await tx.get(db.collection('users').doc(target))).data()||{};
      const active=u=>u.active===true&&u.removed!==true&&u.permissions?.messages!==false;
      const admin=d.senderUid==='tQt6vca2zuagZipvknBwcmSRcrc2'||(active(sender)&&sender.role==='principal');
      const valid=active(receiver)&&['parent','teacher'].includes(receiver.role)
        &&(admin||(d.senderUid===target&&active(sender)))&&d.fromSchool===admin
        &&typeof d.text==='string'&&d.text.length>0&&d.text.length<=2000&&['text','sticker'].includes(d.kind);
      if(valid){
        tx.set(thread,{uid:target,name:receiver.displayName||'',role:receiver.role,updatedAt:FieldValue.serverTimestamp()},{merge:true});
        tx.create(thread.collection('messages').doc('scheduled_'+item.id),{
          text:d.text,kind:d.kind,senderUid:d.senderUid,fromSchool:admin,createdAt:FieldValue.serverTimestamp()
        });
      }
      tx.delete(item.ref);
    });
  }
});

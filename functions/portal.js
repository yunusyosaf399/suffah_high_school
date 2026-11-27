'use strict';

const OWNER_UID = 'tQt6vca2zuagZipvknBwcmSRcrc2';
class PortalError extends Error {
  constructor(status,message) { super(message); this.status=status; }
}
function fail(status,message) { throw new PortalError(status,message); }
function validId(value) { return typeof value==='string' && /^[A-Za-z0-9_-]{1,128}$/.test(value); }
function needId(value) { if(!validId(value)) fail(400,'Invalid record identifier.'); return value; }
function activeAccount(uid,record) {
  if(!record || record.active!==true || record.removed===true) fail(403,'School account is inactive or removed.');
  if(record.role==='owner' && uid!==OWNER_UID) fail(403,'Invalid administrator account.');
  return {...record,uid,role:uid===OWNER_UID?'owner':record.role};
}
function allowed(account,key) { return account.role==='owner' || (account.permissions?.[key]===undefined || account.permissions[key]===true); }
function needPermission(account,key) { if(!allowed(account,key)) fail(403,'This permission is disabled by the school owner.'); }
function linkedChild(account,id) {
  needId(id);
  if(account.role!=='parent' || !Array.isArray(account.linkedStudentIds) || !account.linkedStudentIds.includes(id)) fail(403,'This student is not linked to your account.');
  return id;
}
const pick=(data,keys)=>Object.fromEntries(keys.filter(k=>data[k]!==undefined).map(k=>[k,data[k]]));
const str=(v)=>typeof v==='string'?v:'';
const maxRows=1000;
const profileKeys=['fullName','admissionNo','rollNo','classId','dateOfBirth','gender','admissionDate','status','active'];
const billKeys=['title','month','category','amountMinor','paidMinor','status','currency','dueDate'];
const paperKeys=['title','sessionTitle','category','subject','examDate','paperType','startMinute','endMinute','maxMarks','resultStatus'];
function fileMetadata(student,id) {
  const files=Object.values(student.attachments||{}).filter(f=>f && typeof f==='object');
  if(student.photoPath) files.push({name:'Profile photo.webp',path:student.photoPath,contentType:'image/webp'});
  return files.filter(f=>typeof f.path==='string' &&
    (f.path.startsWith('student-documents/'+id+'/') || f.path.startsWith('student-photos/'+id+'/')))
    .map(f=>pick(f,['name','path','contentType','kind','bytes']));
}
async function childRecord(db,account,id) {
  linkedChild(account,id);
  const snapshot=await db.collection('students').doc(id).get();
  if(!snapshot.exists || snapshot.data().status==='draft') fail(404,'Student record is unavailable.');
  return snapshot.data();
}
async function bounded(query) {
  const result=await query.limit(maxRows+1).get();
  return {docs:result.docs.slice(0,maxRows),truncated:result.docs.length>maxRows};
}
async function parentSection(db,account,id,section) {
  const permissions={profile:'parent_profile',fees:'parent_fees',attendance:'parent_attendance',exams:'parent_exams',documents:'parent_documents'};
  if(!Object.hasOwn(permissions,section)) fail(400,'Unknown parent section.');
  needPermission(account,permissions[section]);
  const student=await childRecord(db,account,id);
  if(section==='profile') {
    const c=str(student.classId);
    const klass=validId(c)?(await db.collection('classes').doc(c).get()).data():null;
    // Admissions store these personal fields under details.student. Only
    // child-profile fields are projected; guardian identifiers, health data,
    // private notes and the complete admission document are never returned.
    const personal=student.details?.student||{};
    const profile={...pick(student,profileKeys),
      ...pick(personal,['dateOfBirth','gender','nationality']),
      className:klass?[klass.name,klass.section].filter(Boolean).join(' – '):c};
    const date=student.details?.academic?.admissionDate;
    if(typeof date==='string' && date) profile.admissionDate=date;
    if(!profile.admissionDate && student.admittedAt?.toDate) profile.admissionDate=student.admittedAt.toDate().toISOString().slice(0,10);
    return {profile};
  }
  if(section==='documents') return {rows:fileMetadata(student,id)};
  if(section==='fees') {
    const result=await bounded(db.collection('finance_fee_bills').where('studentId','==',id));
    return {rows:result.docs.map(d=>pick(d.data(),billKeys)).sort((a,b)=>str(b.month).localeCompare(str(a.month))),truncated:result.truncated};
  }
  // The same marks collection group includes attendance and exams. Filter
  // the exact parent path, never return another student's data or a roster.
  const marks=await bounded(db.collectionGroup('marks').where('studentId','==',id));
  const ownMarks=marks.docs.filter(d=>d.id===id);
  if(section==='attendance') {
    return {rows:ownMarks.filter(d=>d.ref.parent.parent.parent.id==='attendance_days')
      .map(d=>pick(d.data(),['date','status','classId'])).sort((a,b)=>str(b.date).localeCompare(str(a.date))),truncated:marks.truncated};
  }
  const examMarks=ownMarks.filter(d=>d.ref.parent.parent.parent.id==='examinations');
  const markedIds=new Set(examMarks.map(d=>d.ref.parent.parent.id));
  const papers=new Map();
  if(validId(student.classId)) {
    const result=await bounded(db.collection('examinations').where('classId','==',student.classId));
    for(const d of result.docs) papers.set(d.id,d);
    if(result.truncated) marks.truncated=true;
  }
  for(const id of markedIds) {
    if(!papers.has(id)) {
      const d=await db.collection('examinations').doc(id).get();
      if(d.exists) papers.set(id,d);
    }
  }
  const markMap=new Map(examMarks.map(d=>[d.ref.parent.parent.id,d.data()]));
  const cycles=new Map();
  const rows=[];
  for(const [paperId,d] of papers) {
    const p=d.data();
    if(p.active!==true) continue;
    if(Array.isArray(p.expectedStudentIds) && !p.expectedStudentIds.includes(id)) continue;
    if(p.classId!==student.classId && !markMap.has(paperId)) continue;
    if(validId(p.cycleId) && !cycles.has(p.cycleId)) {
      cycles.set(p.cycleId,(await db.collection('exam_term_cycles').doc(p.cycleId).get()).data()||{});
    }
    const cycle=cycles.get(p.cycleId)||{};
    const row={...pick(p,paperKeys),cycleStatus:cycle.status||'',
      schoolClosure:cycle.excludedDates?.[p.examDate]||''};
    if(p.resultStatus==='released' && typeof markMap.get(paperId)?.score==='number') row.score=markMap.get(paperId).score;
    rows.push(row);
  }
  return {rows:rows.sort((a,b)=>str(b.examDate).localeCompare(str(a.examDate))),truncated:marks.truncated};
}
async function teacherSection(db,account,section) {
  if(account.role!=='teacher') fail(403,'Teacher access required.');
  const staffId=needId(account.staffId);
  const staff=(await db.collection('staff').doc(staffId).get()).data();
  if(!staff || staff.active!==true || staff.roleType!=='teacher') fail(403,'Teacher profile is inactive.');
  if(section==='profile') {
    needPermission(account,'teacher_profile');
    const contract=(await db.collection('staff_contracts').doc(staffId).get()).data()||{};
    return {profile:pick(staff,['fullName','staffNo','designation','joinDate','email','phone','qualification','subjectSpecialization']),
      contract:pick(contract,['type','startDate','endDate','details'])};
  }
  if(section==='salary') {
    needPermission(account,'teacher_payroll');
    const result=await bounded(db.collection('finance_salary_bills').where('staffId','==',staffId));
    const rate=(await db.collection('finance_salary_rates').doc(staffId).get()).data()||{};
    return {rate:pick(rate,['basicMinor','allowanceMinor','bonusMinor','amountMinor','currency']),
      rows:result.docs.map(d=>pick(d.data(),[...billKeys,'basicMinor','allowanceMinor','bonusMinor']))
      .sort((a,b)=>str(b.month).localeCompare(str(a.month))),truncated:result.truncated};
  }
  if(section==='analytics') {
    needPermission(account,'teacher_analytics');
    const result=await bounded(db.collection('examinations').where('staffId','==',staffId));
    let released=0,submitted=0,scoreSum=0,scoreCount=0;
    const groups=new Map();
    for(const d of result.docs) {
      const p=d.data(); if(p.active!==true) continue;
      if(p.resultStatus==='submitted') submitted++;
      if(p.resultStatus!=='released') continue;
      released++;
      const key=[p.className||p.classId,p.subject].join(' • ');
      const g=groups.get(key)||{name:key,papers:0,count:0,sum:0};
      g.papers++;
      const marks=await bounded(d.ref.collection('marks'));
      if(marks.truncated) result.truncated=true;
      for(const m of marks.docs) {
        const score=m.data().score;
        if(typeof score==='number' && typeof p.maxMarks==='number' && p.maxMarks>0 && score>=0 && score<=p.maxMarks) {
          const percentage=100*score/p.maxMarks;
          g.sum+=percentage;g.count++;scoreSum+=percentage;scoreCount++;
        }
      }
      groups.set(key,g);
    }
    return {released,submitted,average:scoreCount?scoreSum/scoreCount:null,
      rows:[...groups.values()].map(g=>({name:g.name,papers:g.papers,average:g.count?g.sum/g.count:null,marks:g.count})),truncated:result.truncated};
  }
  fail(400,'Unknown teacher section.');
}
function messageAccess(account) {
  if(!['owner','principal','teacher','parent'].includes(account.role)) fail(403,'Messaging is unavailable for this role.');
  needPermission(account,'messages');
}
function isAdmin(account) { return ['owner','principal'].includes(account.role); }
async function messageThread(db,account,requested) {
  messageAccess(account);
  const uid=isAdmin(account)?needId(requested):account.uid;
  if(!isAdmin(account) && requested && requested!==uid) fail(403,'You may only access your own conversation.');
  const target=activeAccount(uid,(await db.collection('users').doc(uid).get()).data());
  if(!['parent','teacher'].includes(target.role)) fail(403,'Choose a parent or teacher account.');
  return {uid,target,ref:db.collection('portal_threads').doc(uid)};
}
async function portalAction(db,auth,account,body,serverTimestamp) {
  const action=body.action;
  if(action==='children') {
    if(account.role!=='parent') fail(403,'Parent access required.');
    const ids=Array.isArray(account.linkedStudentIds)?[...new Set(account.linkedStudentIds)].filter(validId).slice(0,50):[];
    const rows=[];
    for(const id of ids) {
      const snapshot=await db.collection('students').doc(id).get();
      if(snapshot.exists && snapshot.data().status!=='draft') rows.push({id,name:snapshot.data().fullName||id});
    }
    return {rows};
  }
  if(action==='parentSection') return parentSection(db,account,body.childId,body.section);
  if(action==='authorizeFile') {
    needPermission(account,'parent_documents');
    const student=await childRecord(db,account,body.childId);
    if(!fileMetadata(student,body.childId).some(f=>f.path===body.path)) fail(403,'This file is not linked to your child.');
    return {authorized:true};
  }
  if(action==='teacherSection') return teacherSection(db,account,body.section);
  if(action==='threads') {
    messageAccess(account);
    if(!isAdmin(account)) fail(403,'Administrator access required.');
    // Include users without an existing conversation, so school staff can initiate one.
    const result=await bounded(db.collection('users').where('role','in',['parent','teacher']));
    return {rows:result.docs.filter(d=>d.data().active===true && d.data().removed!==true &&
      d.data().permissions?.messages!==false).map(d=>({uid:d.id,name:d.data().displayName||d.id,role:d.data().role})),truncated:result.truncated};
  }
  if(action==='messages') {
    const {ref}=await messageThread(db,account,body.threadUid);
    const result=await ref.collection('messages').orderBy('createdAt','desc').limit(100).get();
    return {rows:result.docs.reverse().map(d=>{const m=d.data();return {text:m.text,fromSchool:m.fromSchool,
      date:m.createdAt?.toDate().toISOString()||''};}),truncated:result.docs.length===100};
  }
  if(action==='sendMessage') {
    const {ref,uid,target}=await messageThread(db,account,body.threadUid);
    if(!allowed(target,'messages')) fail(403,'Messaging is disabled for this account.');
    const text=str(body.text).trim();
    if(!text || text.length>2000) fail(400,'Enter a message up to 2000 characters.');
    const batch=db.batch();
    batch.set(ref,{uid,updatedAt:serverTimestamp()},{merge:true});
    batch.set(ref.collection('messages').doc(),{text,fromSchool:isAdmin(account),senderUid:account.uid,createdAt:serverTimestamp()});
    await batch.commit();
    return {ok:true};
  }
  if(action==='deleteAuthAccount') {
    if(account.role!=='owner' || account.uid!==OWNER_UID) fail(403,'Only the school owner can delete sign-in accounts.');
    const uid=needId(body.uid);
    if(uid===OWNER_UID) fail(403,'The owner account is protected.');
    const target=(await db.collection('users').doc(uid).get()).data();
    if(!target || target.active!==false || target.removed!==true || target.role==='owner') fail(409,'Remove school access before deleting authentication.');
    try { await auth.deleteUser(uid); } catch(error) { if(error.code!=='auth/user-not-found') throw error; }
    return {ok:true};
  }
  fail(400,'Unknown request.');
}
module.exports={OWNER_UID,PortalError,activeAccount,allowed,linkedChild,fileMetadata,portalAction};

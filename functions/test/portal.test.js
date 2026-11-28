'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {activeAccount,allowed,linkedChild,fileMetadata,portalAction,OWNER_UID}=require('../portal');
const parent=activeAccount('p',{active:true,role:'parent',linkedStudentIds:['S1'],permissions:{parent_documents:false}});
test('inactive or removed accounts and forged owners are rejected',()=>{
  assert.throws(()=>activeAccount('p',{active:false,role:'parent'}));
  assert.throws(()=>activeAccount('p',{active:true,removed:true,role:'teacher'}));
  assert.throws(()=>activeAccount('p',{active:true,role:'owner'}));
  assert.equal(activeAccount(OWNER_UID,{active:true,role:'owner'}).role,'owner');
});
test('child links and feature permissions fail closed for unrelated children',()=>{
  assert.equal(linkedChild(parent,'S1'),'S1');
  assert.throws(()=>linkedChild(parent,'S2'));
  assert.throws(()=>linkedChild(parent,'../S1'));
  assert.equal(allowed(parent,'parent_documents'),false);
  assert.equal(allowed(parent,'parent_fees'),true);
});
test('document metadata never lists another child or arbitrary fields',()=>{
  const result=fileMetadata({photoPath:'student-photos/S1/photo.webp',attachments:{
    a:{path:'student-documents/S1/other/one.pdf',name:'One',privateNote:'hidden'},
    b:{path:'student-documents/S2/other/two.pdf'},
  }},'S1');
  assert.equal(result.length,2);
  assert.equal(result[0].privateNote,undefined);
});
test('parent cannot request other child, disabled documents, teacher salary or account deletion',async()=>{
  const noDb={collection(){throw new Error('unexpected database access');}};
  for(const body of [
    {action:'parentSection',childId:'S2',section:'profile'},
    {action:'parentSection',childId:'S1',section:'documents'},
    {action:'teacherSection',section:'salary'},
    {action:'deleteAuthAccount',uid:'someone'},
  ]) await assert.rejects(portalAction(noDb,{},parent,body,()=>null),e=>e.status===403);
});

test('linked parent receives allowlisted profile fields only',async()=>{
  const profile={fullName:'Child',admissionNo:'S1',classId:'C1',status:'admitted',guardianPhone:'private',medicalHistory:'private',details:{student:{dateOfBirth:'2020-01-01',gender:'Female',nationality:'Pakistan',privateNote:'hidden'},guardian:{email:'private@example.com'},health:{note:'private'}}};
  const db={collection(name){return {doc(id){return {async get(){
    if(name==='students'&&id==='S1')return {exists:true,data:()=>profile};
    if(name==='classes'&&id==='C1')return {exists:true,data:()=>({name:'Grade 1',section:'A'})};
    throw new Error('unexpected record');
  }}}}}};
  const result=await portalAction(db,{},parent,{action:'parentSection',childId:'S1',section:'profile'},()=>null);
  assert.deepEqual(result.profile,{fullName:'Child',admissionNo:'S1',classId:'C1',status:'admitted',dateOfBirth:'2020-01-01',gender:'Female',nationality:'Pakistan',className:'Grade 1 – A'});
});
test('parent file authorization requires linked child and currently referenced path',async()=>{
  const child={status:'admitted',attachments:{birth:{path:'student-documents/S1/birth_certificate/one.pdf'}}};
  const db={collection(){return {doc(){return {async get(){return {exists:true,data:()=>child}}}}}}};
  const account={...parent,permissions:{}};
  assert.deepEqual(await portalAction(db,{},account,{action:'authorizeFile',childId:'S1',path:child.attachments.birth.path},()=>null),{authorized:true});
  await assert.rejects(portalAction(db,{},account,{action:'authorizeFile',childId:'S1',path:'student-documents/S1/other/old.pdf'},()=>null),e=>e.status===403);
  await assert.rejects(portalAction(db,{},account,{action:'authorizeFile',childId:'S2',path:child.attachments.birth.path},()=>null),e=>e.status===403);
});
test('only the account owner can request its private message thread',async()=>{
  const db={collection(){throw new Error('unexpected database access');}};
  await assert.rejects(portalAction(db,{},parent,{action:'messages',threadUid:'another'},()=>null),e=>e.status===403);
  await assert.rejects(portalAction(db,{},parent,{action:'threads'},()=>null),e=>e.status===403);
});

import assert from 'node:assert/strict';
import { test } from 'node:test';
import { authorizeStudent, authorizeParentFile, authorizeStudentPhoto } from '../src/index.js';

const env = { FIREBASE_PROJECT_ID: 'suffah-high-school' };
const token = 'fake-test-id-token';
const studentId = 'ST-2026-0005';

async function withMockFetch(fakeFetch, callback) {
  const original = globalThis.fetch;
  globalThis.fetch = fakeFetch;
  try {
    await callback();
  } finally {
    globalThis.fetch = original;
  }
}

test('Firestore request uses manual redirects, preserving the bearer token', async () => {
  let outgoing;
  await withMockFetch(async (url, options) => {
    outgoing = { url: String(url), ...options };
    return Response.json({ fields: { status: { stringValue: 'draft' } } });
  }, async () => {
    const student = await authorizeStudent(env, token, studentId);
    assert.equal(student.fields.status.stringValue, 'draft');
  });
  assert.match(outgoing.url, /\/documents\/students\/ST-2026-0005$/);
  assert.equal(outgoing.redirect, 'manual');
  assert.equal(outgoing.headers.Authorization, 'Bearer ' + token);
});

test('Firestore redirect is refused without following its Location', async () => {
  let requests = 0;
  await withMockFetch(async () => {
    requests += 1;
    return new Response(null, { status: 302, headers: {
      Location: 'https://unexpected.example/files',
    } });
  }, async () => {
    await assert.rejects(
      () => authorizeStudent(env, token, studentId),
      (error) => error.status === 502 && error.code === 'FIRESTORE_REDIRECT_BLOCKED',
    );
  });
  assert.equal(requests, 1);
});

test('network failure remains distinct from permission rejection', async () => {
  await withMockFetch(async () => {
    throw new TypeError('Network unavailable in mock');
  }, async () => {
    await assert.rejects(
      () => authorizeStudent(env, token, studentId),
      (error) => error.status === 502 && error.code === 'FIRESTORE_REQUEST_FAILED',
    );
  });
});

test('403 is reported as student access denied', async () => {
  await withMockFetch(async () => new Response(null, { status: 403 }), async () => {
    await assert.rejects(
      () => authorizeStudent(env, token, studentId),
      (error) => error.status === 403 && error.code === 'STUDENT_ACCESS_DENIED',
    );
  });
});

test('missing student draft is clearly reported', async () => {
  await withMockFetch(async () => new Response(null, { status: 404 }), async () => {
    await assert.rejects(
      () => authorizeStudent(env, token, studentId),
      (error) => error.status === 404 && error.code === 'STUDENT_NOT_FOUND',
    );
  });
});


test('parent authorization uses Firestore rules and checks the exact referenced file',async()=>{
  const path='student-documents/ST-2026-0005/other/11111111-1111-1111-1111-111111111111.pdf';
  await withMockFetch(async(url,options)=>{
    assert.match(String(url),/\/documents\/parent_documents\/ST-2026-0005$/);
    assert.equal(options.redirect,'manual');
    assert.equal(options.headers.Authorization,'Bearer '+token);
    return Response.json({fields:{attachments:{mapValue:{fields:{one:{mapValue:{fields:{path:{stringValue:path}}}}}}}}});
  },()=>authorizeParentFile(env,token,path));
  await withMockFetch(async()=>Response.json({fields:{}}),async()=>{
    await assert.rejects(()=>authorizeParentFile(env,token,path),e=>e.status===403);
  });
  await withMockFetch(async()=>new Response(null,{status:403}),async()=>{
    await assert.rejects(()=>authorizeParentFile(env,token,path),e=>e.status===403);
  });
  await withMockFetch(async()=>new Response(null,{status:302,headers:{Location:'https://unexpected.example'}}),async()=>{
    await assert.rejects(()=>authorizeParentFile(env,token,path),e=>e.status===502);
  });
});

test('photo-only authorization falls back to scoped directory and rejects other student files',async()=>{
  const path='student-photos/ST-2026-0005/11111111-1111-1111-1111-111111111111.webp';
  await withMockFetch(async(url)=>String(url).includes('/documents/students/')?
    new Response(null,{status:403}):Response.json({fields:{photoPath:{stringValue:path}}}),
    async()=>assert.equal(await authorizeStudentPhoto(env,token,studentId),path));
  await withMockFetch(async()=>Response.json({fields:{photoPath:{stringValue:path.replace(studentId,'ST-2026-0006')}}}),
    async()=>assert.rejects(()=>authorizeStudentPhoto(env,token,studentId),e=>e.status===403));
  await withMockFetch(async()=>new Response(null,{status:403}),
    async()=>assert.rejects(()=>authorizeStudentPhoto(env,token,studentId),e=>e.status===403));
});

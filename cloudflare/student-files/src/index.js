import { createRemoteJWKSet, jwtVerify } from 'jose';

// Student files are deliberately PRIVATE. Never expose an R2 public URL or key.
const firebaseKeys = createRemoteJWKSet(
  new URL('https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com'),
);
const studentPattern = /^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$/;
const documentKinds = new Set([
  'birth_certificate', 'transfer_certificate',
  'previous_school_certificate', 'medical_report', 'other',
]);
const documentMimeTypes = {
  'application/pdf': 'pdf',
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
};
const maxPhotoBytes = 100 * 1024;
const maxDocumentBytes = 5 * 1024 * 1024;

class ApiError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

function json(data, status = 200) {
  return Response.json(data, {
    status,
    headers: { 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' },
  });
}

function studentFromPath(path) {
  const photo = /^student-photos\/([A-Za-z0-9_-]{1,64})\/[a-f0-9-]{36}\.webp$/.exec(path);
  if (photo) return photo[1];
  const document = /^student-documents\/([A-Za-z0-9_-]{1,64})\/([a-z_]+)\/[a-f0-9-]{36}\.(pdf|jpg|png|webp)$/.exec(path);
  if (document && documentKinds.has(document[2])) return document[1];
  throw new ApiError(400, 'Invalid or unsupported R2 file path.');
}

async function firebaseToken(request, projectId) {
  const header = request.headers.get('Authorization') || '';
  const match = /^Bearer ([^\s]+)$/.exec(header);
  if (!match) throw new ApiError(401, 'Sign in to your school account first.');
  try {
    const { payload } = await jwtVerify(match[1], firebaseKeys, {
      issuer: 'https://securetoken.google.com/' + projectId,
      audience: projectId,
      algorithms: ['RS256'],
    });
    const now = Math.floor(Date.now() / 1000);
    if (!payload.sub || payload.sub.length > 128 ||
        typeof payload.auth_time !== 'number' || payload.auth_time > now) {
      throw new Error('Invalid Firebase ID token claims.');
    }
    return match[1];
  } catch (_) {
    throw new ApiError(401, 'School sign-in expired. Sign in again.');
  }
}

// Firestore REST with a Firebase ID token ENFORCES the same students/{id}
// security rule as the Flutter client. No service-account/admin bypass.
async function authorizeStudent(env, token, studentId) {
  if (!studentPattern.test(studentId)) {
    throw new ApiError(400, 'Invalid student registration number.');
  }
  const url = 'https://firestore.googleapis.com/v1/projects/' +
    encodeURIComponent(env.FIREBASE_PROJECT_ID) +
    '/databases/(default)/documents/students/' + encodeURIComponent(studentId);
  const response = await fetch(url, {
    headers: { Authorization: 'Bearer ' + token },
    redirect: 'error',
  });
  if (response.status === 401 || response.status === 403) {
    throw new ApiError(403, 'Your account may not access this student.');
  }
  if (response.status === 404) throw new ApiError(404, 'Student record not found.');
  if (!response.ok) throw new ApiError(502, 'Could not verify school permissions.');
  return response.json();
}

async function limitedBody(request, limit) {
  const claimed = Number(request.headers.get('Content-Length'));
  if (Number.isFinite(claimed) && claimed > limit) {
    throw new ApiError(413, 'File exceeds the upload size limit.');
  }
  if (!request.body) throw new ApiError(400, 'Choose a file before uploading.');
  const reader = request.body.getReader();
  const chunks = [];
  let bytes = 0;
  try {
    while (true) {
      const next = await reader.read();
      if (next.done) break;
      bytes += next.value.byteLength;
      if (bytes > limit) {
        await reader.cancel();
        throw new ApiError(413, 'File exceeds the upload size limit.');
      }
      chunks.push(next.value);
    }
  } finally {
    reader.releaseLock();
  }
  if (!bytes) throw new ApiError(400, 'The selected file is empty.');
  const result = new Uint8Array(bytes);
  let offset = 0;
  for (const chunk of chunks) {
    result.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return result;
}

function isWebp(bytes) {
  return bytes.length >= 12 &&
    String.fromCharCode(...bytes.slice(0, 4)) === 'RIFF' &&
    String.fromCharCode(...bytes.slice(8, 12)) === 'WEBP';
}

function isValidDocument(bytes, type) {
  if (type === 'application/pdf') {
    return bytes.length >= 5 && String.fromCharCode(...bytes.slice(0, 5)) === '%PDF-';
  }
  if (type === 'image/jpeg') {
    return bytes.length >= 3 && bytes[0] === 0xff &&
      bytes[1] === 0xd8 && bytes[2] === 0xff;
  }
  if (type === 'image/png') {
    return bytes.length >= 8 &&
      [137, 80, 78, 71, 13, 10, 26, 10].every((b, i) => bytes[i] === b);
  }
  if (type === 'image/webp') return isWebp(bytes);
  return false;
}

function stillReferenced(student, path) {
  const fields = student.fields || {};
  if (fields.photoPath?.stringValue === path) return true;
  const files = fields.attachments?.mapValue?.fields || {};
  return Object.values(files).some((value) =>
    value?.mapValue?.fields?.path?.stringValue === path);
}

async function handle(request, env) {
  if (!env.STUDENT_FILES || !env.FIREBASE_PROJECT_ID) {
    throw new ApiError(503, 'R2 storage is not configured on this Worker.');
  }
  const url = new URL(request.url);
  if (request.method === 'GET' && url.pathname === '/health') {
    return json({ status: 'ok' });
  }
  const token = await firebaseToken(request, env.FIREBASE_PROJECT_ID);

  const upload = /^\/v1\/students\/([^/]+)\/(photo|documents\/([a-z_]+))$/.exec(url.pathname);
  if (request.method === 'PUT' && upload) {
    const studentId = upload[1];
    const isPhoto = upload[2] === 'photo';
    const kind = upload[3] || '';
    if (!isPhoto && !documentKinds.has(kind)) {
      throw new ApiError(400, 'Unsupported document category.');
    }
    await authorizeStudent(env, token, studentId);
    const type = (request.headers.get('Content-Type') || '').split(';')[0].trim().toLowerCase();
    const limit = isPhoto ? maxPhotoBytes : maxDocumentBytes;
    const bytes = await limitedBody(request, limit);
    if (isPhoto ? (type !== 'image/webp' || !isWebp(bytes))
                : (!documentMimeTypes[type] || !isValidDocument(bytes, type))) {
      throw new ApiError(415, 'File format does not match its content.');
    }
    const extension = isPhoto ? 'webp' : documentMimeTypes[type];
    const path = isPhoto
      ? 'student-photos/' + studentId + '/' + crypto.randomUUID() + '.webp'
      : 'student-documents/' + studentId + '/' + kind + '/' + crypto.randomUUID() + '.' + extension;
    await env.STUDENT_FILES.put(path, bytes, {
      httpMetadata: { contentType: type },
      customMetadata: { schoolStudentId: studentId },
    });
    const proposedName = request.headers.get('X-File-Name') || (isPhoto ? 'profile.webp' : kind + '.' + extension);
    const name = proposedName.replace(/[^a-zA-Z0-9._ -]/g, '_').slice(0, 100);
    return json({ path, name, contentType: type, kind: isPhoto ? 'photo' : kind, bytes: bytes.length }, 201);
  }

  if (url.pathname === '/v1/files' && (request.method === 'GET' || request.method === 'DELETE')) {
    const path = url.searchParams.get('path') || '';
    const studentId = studentFromPath(path);
    const student = await authorizeStudent(env, token, studentId);
    if (request.method === 'DELETE') {
      // Prevent deletion of any object referenced by the current student profile.
      if (stillReferenced(student, path)) {
        throw new ApiError(409, 'Remove this file from the student record before deleting it.');
      }
      await env.STUDENT_FILES.delete(path);
      return new Response(null, { status: 204, headers: { 'Cache-Control': 'no-store' } });
    }
    const object = await env.STUDENT_FILES.get(path);
    if (!object) throw new ApiError(404, 'File not found in Cloudflare R2.');
    return new Response(object.body, {
      headers: {
        'Content-Type': object.httpMetadata?.contentType || 'application/octet-stream',
        'Content-Disposition': 'attachment',
        'Cache-Control': 'private, no-store',
        'X-Content-Type-Options': 'nosniff',
      },
    });
  }
  throw new ApiError(404, 'Endpoint not found.');
}

export default {
  async fetch(request, env) {
    try {
      return await handle(request, env);
    } catch (error) {
      if (error instanceof ApiError) return json({ error: error.message }, error.status);
      return json({ error: 'Storage service temporarily unavailable.' }, 500);
    }
  },
};
